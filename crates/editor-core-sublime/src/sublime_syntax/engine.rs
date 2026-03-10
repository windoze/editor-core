use crate::sublime_syntax::compiler::{
    CompiledContext, CompiledIncludePattern, CompiledMatchPattern, CompiledPattern, ContextPush,
    ContextSpec, MatchAction, SublimeSyntax,
};
use crate::sublime_syntax::definition::ClearScopes;
use crate::sublime_syntax::error::SublimeSyntaxError;
use crate::sublime_syntax::scope::SublimeScopeMapper;
use crate::sublime_syntax::set::SublimeSyntaxSet;
use editor_core::LineIndex;
use editor_core::intervals::{FoldRegion, Interval, StyleId};
use onig::{Regex, Region, SearchOptions};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

#[derive(Debug, Default)]
/// Highlighting output produced by [`highlight_document`].
pub struct SublimeHighlightResult {
    /// Style intervals in character offsets.
    pub intervals: Vec<Interval>,
    /// Fold regions inferred from multi-line contexts.
    pub fold_regions: Vec<FoldRegion>,
}

/// Highlights a document and derives fold regions from multi-line contexts.
///
/// - Intervals are in **char offsets**, consistent with `LineIndex` and the rest of editor-core.
/// - The returned intervals are non-overlapping within this result (best-effort).
pub fn highlight_document(
    syntax: Arc<SublimeSyntax>,
    line_index: &LineIndex,
    syntax_set: Option<&mut SublimeSyntaxSet>,
    scope_mapper: &mut SublimeScopeMapper,
) -> Result<SublimeHighlightResult, SublimeSyntaxError> {
    let mut syntax_set = syntax_set;
    let mut engine = Highlighter::new(syntax, scope_mapper);
    engine.highlight(line_index, &mut syntax_set)
}

#[derive(Debug, Clone)]
struct Cursor {
    line: usize,
    pos_byte: usize,
    pos_char: usize,
}

impl Cursor {
    fn new(line: usize) -> Self {
        Self {
            line,
            pos_byte: 0,
            pos_char: 0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ApplyResult {
    Continue,
    Rewind,
}

#[derive(Debug, Clone)]
struct BranchFrame {
    name: String,
    cursor: Cursor,
    context_stack: Vec<ContextFrame>,
    intervals_len: usize,
    fold_regions_len: usize,
    branches: Vec<ContextSpec>,
    next_branch_index: usize,
    match_captures: Arc<Vec<String>>,
}

struct Highlighter<'a> {
    root_syntax: Arc<SublimeSyntax>,
    scope_mapper: &'a mut SublimeScopeMapper,
    pattern_cache: PatternCache,
    dynamic_regex_cache: HashMap<(String, Vec<String>), Arc<Regex>>,
    context_stack: Vec<ContextFrame>,
    branch_stack: Vec<BranchFrame>,
    intervals: Vec<Interval>,
    fold_regions: Vec<FoldRegion>,
}

impl<'a> Highlighter<'a> {
    fn new(syntax: Arc<SublimeSyntax>, scope_mapper: &'a mut SublimeScopeMapper) -> Self {
        Self {
            root_syntax: syntax,
            scope_mapper,
            pattern_cache: PatternCache::default(),
            dynamic_regex_cache: HashMap::new(),
            context_stack: Vec::new(),
            branch_stack: Vec::new(),
            intervals: Vec::new(),
            fold_regions: Vec::new(),
        }
    }

    fn highlight(
        &mut self,
        line_index: &LineIndex,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<SublimeHighlightResult, SublimeSyntaxError> {
        if !self.root_syntax.contexts.contains_key("main") {
            return Err(SublimeSyntaxError::MissingField("contexts.main"));
        }

        self.context_stack.push(ContextFrame::named(
            self.root_syntax.clone(),
            "main".to_string(),
            0,
        ));

        let base_scope = self.root_syntax.scope.clone();
        let line_count = line_index.line_count();

        let mut cursor = Cursor::new(0);
        let mut rewind_count = 0usize;
        let max_rewinds = line_count.saturating_mul(64).max(256);

        'doc: while cursor.line < line_count {
            let mut line_text = line_index.get_line_text(cursor.line).unwrap_or_default();
            // `LineIndex::get_line_text` strips the trailing '\n'. Many `.sublime-syntax` regexes
            // explicitly match `\n` at EOL, so we re-add it for all but the last line.
            if cursor.line + 1 < line_count {
                line_text.push('\n');
            }
            let line_start_offset = line_index.position_to_char_offset(cursor.line, 0);

            // Clamp in case a bad rewind points past EOL (defensive).
            if cursor.pos_byte > line_text.len() {
                cursor.pos_byte = line_text.len();
            }

            let line_len_bytes = line_text.len();

            // Prevent infinite loops with zero-width matches.
            // Sublime itself has more nuanced behavior; we keep a generous bound.
            let mut iterations = 0usize;
            let max_iterations = (line_len_bytes + 1).saturating_mul(32).max(128);

            while cursor.pos_byte <= line_len_bytes {
                iterations += 1;
                if iterations > max_iterations {
                    return Err(SublimeSyntaxError::Unsupported(
                        "highlighting exceeded iteration limit (possible zero-width loop)",
                    ));
                }

                let Some(found) = self.find_next_match(&line_text, cursor.pos_byte, syntax_set)?
                else {
                    let end_char = cursor.pos_char + line_text[cursor.pos_byte..].chars().count();
                    let style = self.best_style_for_content();
                    self.emit_segment(
                        line_start_offset + cursor.pos_char,
                        line_start_offset + end_char,
                        style,
                        base_scope.as_str(),
                    );
                    break;
                };

                // Emit content before the match.
                if found.start_byte > cursor.pos_byte {
                    let segment_chars =
                        line_text[cursor.pos_byte..found.start_byte].chars().count();
                    let end_char = cursor.pos_char + segment_chars;
                    let style = self.best_style_for_content();
                    self.emit_segment(
                        line_start_offset + cursor.pos_char,
                        line_start_offset + end_char,
                        style,
                        base_scope.as_str(),
                    );
                    cursor.pos_char = end_char;
                    cursor.pos_byte = found.start_byte;
                }

                // Emit match region (may be empty for lookaheads).
                if found.end_byte > found.start_byte {
                    let match_chars =
                        line_text[found.start_byte..found.end_byte].chars().count();
                    let end_char = cursor.pos_char + match_chars;

                    let style = self.best_style_for_match(&found.pattern);
                    self.emit_segment(
                        line_start_offset + cursor.pos_char,
                        line_start_offset + end_char,
                        style,
                        base_scope.as_str(),
                    );

                    cursor.pos_char = end_char;
                    cursor.pos_byte = found.end_byte;
                }

                let stack_len_before = self.context_stack.len();
                let match_captures =
                    Arc::new(extract_captures(line_text.as_str(), &found.capture_positions));
                match self.apply_action(
                    found.pattern.action.clone(),
                    match_captures,
                    &mut cursor,
                    syntax_set,
                )? {
                    ApplyResult::Continue => {}
                    ApplyResult::Rewind => {
                        rewind_count += 1;
                        if rewind_count > max_rewinds {
                            return Err(SublimeSyntaxError::Unsupported(
                                "branch backtracking exceeded limit",
                            ));
                        }
                        continue 'doc;
                    }
                }
                let stack_len_after = self.context_stack.len();

                // If this is a zero-width match and the stack didn't change, we must
                // ensure progress to avoid an infinite loop. At end-of-line we can
                // stop since there is nothing left to consume.
                if found.start_byte == found.end_byte
                    && found.start_byte == cursor.pos_byte
                    && stack_len_before == stack_len_after
                {
                    if cursor.pos_byte >= line_len_bytes {
                        break;
                    }

                    // Advance by one UTF-8 char boundary.
                    let mut iter = line_text[cursor.pos_byte..].char_indices();
                    let _ = iter.next();
                    if let Some((next_rel, _)) = iter.next() {
                        cursor.pos_byte += next_rel;
                        cursor.pos_char += 1;
                    } else {
                        // Single remaining char.
                        cursor.pos_byte = line_len_bytes;
                        cursor.pos_char += 1;
                    }
                }
            }

            // Next line.
            cursor.line += 1;
            cursor.pos_byte = 0;
            cursor.pos_char = 0;
        }

        // Close any remaining contexts at EOF for folding purposes.
        let last_line = line_count.saturating_sub(1);
        while self.context_stack.len() > 1 {
            self.pop_one_context(last_line);
        }

        Ok(SublimeHighlightResult {
            intervals: std::mem::take(&mut self.intervals),
            fold_regions: std::mem::take(&mut self.fold_regions),
        })
    }

    fn emit_segment(
        &mut self,
        start: usize,
        end: usize,
        style_id: StyleId,
        base_scope: &str,
    ) {
        let intervals = &mut self.intervals;
        if start >= end {
            return;
        }

        // Skip base scope to keep intervals smaller; consumers can treat "no style"
        // as the base.
        if self
            .scope_mapper
            .scope_for_style_id(style_id)
            .is_some_and(|s| s == base_scope)
        {
            return;
        }

        if let Some(last) = intervals.last_mut()
            && last.style_id == style_id
            && last.end == start
        {
            last.end = end;
            return;
        }

        intervals.push(Interval::new(start, end, style_id));
    }

    fn find_next_match(
        &mut self,
        line_text: &str,
        from_byte: usize,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Option<FoundMatch>, SublimeSyntaxError> {
        let Some(top) = self.context_stack.last() else {
            return Ok(None);
        };

        let snapshot = top.snapshot();
        let patterns = self.flatten_patterns_for_snapshot(&snapshot, syntax_set)?;
        let backref_captures = self.current_backref_captures().to_vec();

        let mut best: Option<FoundMatch> = None;
        for pattern in patterns {
            let regex = self.regex_for_pattern(&pattern, &backref_captures)?;
            let Some(region) = search_first_region(&regex, line_text, from_byte)? else {
                continue;
            };
            let Some((start, end)) = region.pos(0) else {
                continue;
            };
            let mut capture_positions = Vec::with_capacity(region.len());
            for i in 0..region.len() {
                capture_positions.push(region.pos(i));
            }

            match &best {
                None => {
                    best = Some(FoundMatch {
                        start_byte: start,
                        end_byte: end,
                        capture_positions,
                        pattern,
                    });
                }
                Some(existing) => {
                    if start < existing.start_byte {
                        best = Some(FoundMatch {
                            start_byte: start,
                            end_byte: end,
                            capture_positions,
                            pattern,
                        });
                    } else if start == existing.start_byte {
                        // Tie-break by definition order: since we iterate in order,
                        // keep the first one.
                    }
                }
            }
        }

        Ok(best)
    }

    fn current_backref_captures(&self) -> &[String] {
        for frame in self.context_stack.iter().rev() {
            if frame.captures.len() > 1 {
                return frame.captures.as_ref();
            }
        }
        &[]
    }

    fn regex_for_pattern(
        &mut self,
        pattern: &CompiledMatchPattern,
        backref_captures: &[String],
    ) -> Result<Arc<Regex>, SublimeSyntaxError> {
        if let Some(re) = &pattern.regex {
            return Ok(re.clone());
        }

        let key = (pattern.regex_source.clone(), backref_captures.to_vec());
        if let Some(cached) = self.dynamic_regex_cache.get(&key) {
            return Ok(cached.clone());
        }

        let realized = substitute_context_backrefs(&pattern.regex_source, backref_captures);
        let regex = Regex::new(&realized).map_err(|e| SublimeSyntaxError::RegexCompile {
            pattern: realized.clone(),
            message: e.to_string(),
        })?;
        let regex = Arc::new(regex);
        self.dynamic_regex_cache.insert(key, regex.clone());
        Ok(regex)
    }

    fn flatten_patterns_for_snapshot(
        &mut self,
        frame: &ContextFrameSnapshot,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let ctx = frame.context()?;
        if frame.is_inline {
            return self.flatten_inline_context_patterns(frame, ctx, syntax_set);
        }

        let mut base_patterns = self.pattern_cache.flatten_named_context(
            &frame.syntax,
            &frame.context_name,
            syntax_set.as_deref_mut(),
        )?;

        if frame.injected_patterns.is_empty() {
            return Ok(base_patterns);
        }

        let mut out = Vec::new();
        let mut visiting = HashSet::new();
        for injected in &frame.injected_patterns {
            self.flatten_compiled_pattern(
                &frame.syntax,
                injected,
                syntax_set.as_deref_mut(),
                &mut out,
                &mut visiting,
            )?;
        }
        out.append(&mut base_patterns);
        Ok(out)
    }

    fn flatten_inline_context_patterns(
        &mut self,
        frame: &ContextFrameSnapshot,
        ctx: &CompiledContext,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let mut out = Vec::new();

        // Injected patterns (from `with_prototype`) come first.
        for injected in &frame.injected_patterns {
            self.flatten_compiled_pattern(
                &frame.syntax,
                injected,
                syntax_set.as_deref_mut(),
                &mut out,
                &mut HashSet::new(),
            )?;
        }

        // Prototype context if present & enabled.
        if ctx.include_prototype
            && frame.syntax.prototype_exists
            && frame.context_name != "prototype"
        {
            let proto = self.pattern_cache.flatten_named_context(
                &frame.syntax,
                "prototype",
                syntax_set.as_deref_mut(),
            )?;
            out.extend(proto);
        }

        // Then inline context patterns.
        for pattern in &ctx.patterns {
            self.flatten_compiled_pattern(
                &frame.syntax,
                pattern,
                syntax_set.as_deref_mut(),
                &mut out,
                &mut HashSet::new(),
            )?;
        }

        Ok(out)
    }

    fn flatten_compiled_pattern(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        pattern: &CompiledPattern,
        syntax_set: Option<&mut SublimeSyntaxSet>,
        out: &mut Vec<CompiledMatchPattern>,
        visiting: &mut HashSet<(String, String)>,
    ) -> Result<(), SublimeSyntaxError> {
        match pattern {
            CompiledPattern::Match(m) => {
                out.push(m.clone());
            }
            CompiledPattern::Include(i) => {
                self.flatten_include(syntax, i, syntax_set, out, visiting)?;
            }
        }
        Ok(())
    }

    fn flatten_include(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        include: &CompiledIncludePattern,
        mut syntax_set: Option<&mut SublimeSyntaxSet>,
        out: &mut Vec<CompiledMatchPattern>,
        visiting: &mut HashSet<(String, String)>,
    ) -> Result<(), SublimeSyntaxError> {
        let target = include.include.as_str();

        // External syntax include: include the referenced syntax's main context.
        if is_external_syntax_reference(target) {
            // Best-effort: hosts often ship only a single `.sublime-syntax` file.
            // If we can't resolve the external syntax, just skip this include.
            if let Some(set) = syntax_set.as_deref_mut()
                && let Ok(other) = set.load_by_reference(target)
            {
                let other_patterns =
                    self.pattern_cache
                        .flatten_named_context(&other, "main", Some(set))?;
                out.extend(other_patterns);
            }
            return Ok(());
        }

        let key = (syntax.scope.clone(), target.to_string());
        if !visiting.insert(key.clone()) {
            return Err(SublimeSyntaxError::Unsupported(
                "include cycle detected while expanding contexts",
            ));
        }

        // Prototype injection for included contexts is handled by flatten_named_context.
        let patterns = self
            .pattern_cache
            .flatten_named_context(syntax, target, syntax_set)?;
        out.extend(patterns);

        visiting.remove(&key);
        Ok(())
    }

    fn best_style_for_content(&mut self) -> StyleId {
        let scopes = compute_scopes(
            &self.context_stack,
            ScopeMode::Content,
            None,
            &self.root_syntax.scope,
        );
        let best = scopes
            .last()
            .map(|s| s.as_str())
            .unwrap_or(&self.root_syntax.scope);
        self.scope_mapper.style_id_for_scope(best)
    }

    fn best_style_for_match(&mut self, pattern: &CompiledMatchPattern) -> StyleId {
        let scopes = compute_scopes(
            &self.context_stack,
            ScopeMode::Match,
            Some(&pattern.scope),
            &self.root_syntax.scope,
        );
        let best = scopes
            .last()
            .map(|s| s.as_str())
            .unwrap_or(&self.root_syntax.scope);
        self.scope_mapper.style_id_for_scope(best)
    }

    fn apply_action(
        &mut self,
        action: MatchAction,
        match_captures: Arc<Vec<String>>,
        cursor: &mut Cursor,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<ApplyResult, SublimeSyntaxError> {
        match action {
            MatchAction::None => Ok(ApplyResult::Continue),
            MatchAction::Pop { count } => {
                for _ in 0..count {
                    self.pop_one_context(cursor.line);
                }
                Ok(ApplyResult::Continue)
            }
            MatchAction::Branch {
                branch_point,
                branches,
            } => {
                self.apply_branch(branch_point, branches, match_captures, cursor, syntax_set)?;
                Ok(ApplyResult::Continue)
            }
            MatchAction::Fail { branch_point } => {
                self.apply_fail(branch_point, cursor, syntax_set)?;
                Ok(ApplyResult::Rewind)
            }
            MatchAction::Push {
                pop_before,
                push,
                with_prototype,
            } => {
                let mut inherited = self
                    .context_stack
                    .last()
                    .map(|f| f.injected_patterns.clone())
                    .unwrap_or_default();
                inherited.extend(with_prototype);
                for _ in 0..pop_before {
                    self.pop_one_context(cursor.line);
                }
                self.push_contexts(push, inherited, match_captures, cursor.line, syntax_set)?;
                Ok(ApplyResult::Continue)
            }
            MatchAction::Set {
                pop_before,
                set,
                with_prototype,
            } => {
                let mut inherited = self
                    .context_stack
                    .last()
                    .map(|f| f.injected_patterns.clone())
                    .unwrap_or_default();
                inherited.extend(with_prototype);
                for _ in 0..pop_before {
                    self.pop_one_context(cursor.line);
                }
                self.pop_one_context(cursor.line);
                self.push_contexts(set, inherited, match_captures, cursor.line, syntax_set)?;
                Ok(ApplyResult::Continue)
            }
            MatchAction::Embed {
                pop_before,
                embed,
                embed_scope,
                escape_source,
                escape,
                escape_captures,
                with_prototype,
                ..
            } => {
                let mut inherited = self
                    .context_stack
                    .last()
                    .map(|f| f.injected_patterns.clone())
                    .unwrap_or_default();
                inherited.extend(with_prototype);

                for _ in 0..pop_before {
                    self.pop_one_context(cursor.line);
                }

                let wrapper_syntax = self
                    .context_stack
                    .last()
                    .map(|f| f.syntax.clone())
                    .unwrap_or_else(|| self.root_syntax.clone());

                // Wrapper context that applies the `embed_scope` while the embedded syntax is active.
                // We keep this as an inline context so we don't need to mutate the syntax definition.
                let wrapper_ctx = CompiledContext {
                    meta_scope: embed_scope,
                    meta_content_scope: Vec::new(),
                    include_prototype: false,
                    clear_scopes: None,
                    patterns: Vec::new(),
                    meta_prepend: false,
                    meta_append: false,
                };
                self.context_stack.push(ContextFrame::inline_with_injected(
                    wrapper_syntax.clone(),
                    wrapper_ctx,
                    Vec::new(),
                    match_captures.clone(),
                    cursor.line,
                ));

                // Escape match injected *before* embedded patterns to ensure termination wins.
                let escape_scope = escape_captures.get(&0).cloned().unwrap_or_default();
                let (escape_source, escape) = match escape {
                    Some(re) => (escape_source, re),
                    None => {
                        let realized =
                            substitute_context_backrefs(&escape_source, match_captures.as_ref());
                        let regex = Regex::new(&realized).map_err(|e| {
                            SublimeSyntaxError::RegexCompile {
                                pattern: realized.clone(),
                                message: e.to_string(),
                            }
                        })?;
                        (realized, Arc::new(regex))
                    }
                };
                let escape_match = CompiledMatchPattern {
                    origin_scope: wrapper_syntax.scope.clone(),
                    regex_source: escape_source,
                    regex: Some(escape),
                    scope: escape_scope,
                    captures: escape_captures,
                    action: MatchAction::Pop { count: 2 },
                };

                let mut injected = Vec::<CompiledPattern>::new();
                injected.push(CompiledPattern::Match(escape_match));
                injected.extend(inherited);

                // `embed` can point at either:
                // - another syntax (`scope:...`, `Packages/...`, path)
                // - a context name inside the current syntax
                if is_external_syntax_reference(&embed) {
                    // Best-effort: if the embedded syntax cannot be resolved (common when the host
                    // only ships a single `.sublime-syntax` file), fall back to a plain context that
                    // only supports the escape pattern.
                    if let Some(set) = syntax_set.as_deref_mut() {
                        match set.load_by_reference(&embed) {
                            Ok(embedded) => {
                                self.context_stack.push(ContextFrame::named_with_injected(
                                    embedded,
                                    "main".to_string(),
                                    injected,
                                    match_captures.clone(),
                                    cursor.line,
                                ));
                            }
                            Err(_) => {
                                let empty_ctx = CompiledContext {
                                    meta_scope: Vec::new(),
                                    meta_content_scope: Vec::new(),
                                    include_prototype: false,
                                    clear_scopes: None,
                                    patterns: Vec::new(),
                                    meta_prepend: false,
                                    meta_append: false,
                                };
                                self.context_stack.push(ContextFrame::inline_with_injected(
                                    wrapper_syntax,
                                    empty_ctx,
                                    injected,
                                    match_captures.clone(),
                                    cursor.line,
                                ));
                            }
                        }
                    } else {
                        let empty_ctx = CompiledContext {
                            meta_scope: Vec::new(),
                            meta_content_scope: Vec::new(),
                            include_prototype: false,
                            clear_scopes: None,
                            patterns: Vec::new(),
                            meta_prepend: false,
                            meta_append: false,
                        };
                        self.context_stack.push(ContextFrame::inline_with_injected(
                            wrapper_syntax,
                            empty_ctx,
                            injected,
                            match_captures.clone(),
                            cursor.line,
                        ));
                    }
                } else {
                    self.context_stack.push(ContextFrame::named_with_injected(
                        wrapper_syntax,
                        embed,
                        injected,
                        match_captures,
                        cursor.line,
                    ));
                }

                Ok(ApplyResult::Continue)
            }
        }
    }

    fn apply_branch(
        &mut self,
        branch_point: String,
        branches: Vec<ContextSpec>,
        match_captures: Arc<Vec<String>>,
        cursor: &Cursor,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<(), SublimeSyntaxError> {
        let Some(first) = branches.first().cloned() else {
            return Err(SublimeSyntaxError::Unsupported("empty branch list"));
        };

        // Only keep the most recent branch point of a given name; this matches how
        // real-world syntaxes (e.g. Markdown) reuse branch point names at EOL.
        self.branch_stack.retain(|b| b.name != branch_point);

        self.branch_stack.push(BranchFrame {
            name: branch_point,
            cursor: cursor.clone(),
            context_stack: self.context_stack.clone(),
            intervals_len: self.intervals.len(),
            fold_regions_len: self.fold_regions.len(),
            branches,
            next_branch_index: 1,
            match_captures: match_captures.clone(),
        });

        let inherited = self
            .context_stack
            .last()
            .map(|f| f.injected_patterns.clone())
            .unwrap_or_default();
        self.push_context_spec(first, inherited, match_captures, cursor.line, syntax_set)
    }

    fn apply_fail(
        &mut self,
        branch_point: String,
        cursor: &mut Cursor,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<(), SublimeSyntaxError> {
        let Some(idx) = self
            .branch_stack
            .iter()
            .rposition(|b| b.name == branch_point)
        else {
            return Err(SublimeSyntaxError::Unsupported(
                "fail without matching branch_point",
            ));
        };

        let (
            snapshot_cursor,
            snapshot_context_stack,
            intervals_len,
            fold_regions_len,
            next_spec,
            match_captures,
        ) = {
            let frame = self.branch_stack.get_mut(idx).expect("idx checked");
            if frame.next_branch_index >= frame.branches.len() {
                return Err(SublimeSyntaxError::Unsupported("branch exhausted"));
            }
            let next_spec = frame.branches[frame.next_branch_index].clone();
            frame.next_branch_index += 1;
            (
                frame.cursor.clone(),
                frame.context_stack.clone(),
                frame.intervals_len,
                frame.fold_regions_len,
                next_spec,
                frame.match_captures.clone(),
            )
        };

        // Any branch points created after this one are no longer valid after rewinding.
        self.branch_stack.truncate(idx + 1);

        // Restore engine state to the branch point snapshot.
        self.context_stack = snapshot_context_stack;
        self.intervals.truncate(intervals_len);
        self.fold_regions.truncate(fold_regions_len);
        *cursor = snapshot_cursor;

        // Enter the next alternative branch.
        let inherited = self
            .context_stack
            .last()
            .map(|f| f.injected_patterns.clone())
            .unwrap_or_default();
        self.push_context_spec(next_spec, inherited, match_captures, cursor.line, syntax_set)?;

        Ok(())
    }

    fn push_contexts(
        &mut self,
        push: ContextPush,
        with_prototype: Vec<CompiledPattern>,
        captures: Arc<Vec<String>>,
        line: usize,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<(), SublimeSyntaxError> {
        match push {
            ContextPush::One(spec) => {
                self.push_context_spec(spec, with_prototype, captures, line, syntax_set)
            }
            ContextPush::Many(specs) => {
                for spec in specs {
                    self.push_context_spec(
                        spec,
                        with_prototype.clone(),
                        captures.clone(),
                        line,
                        syntax_set,
                    )?;
                }
                Ok(())
            }
        }
    }

    fn push_context_spec(
        &mut self,
        spec: ContextSpec,
        injected_patterns: Vec<CompiledPattern>,
        captures: Arc<Vec<String>>,
        line: usize,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<(), SublimeSyntaxError> {
        match spec {
            ContextSpec::Named { origin_scope, name } => {
                if is_external_syntax_reference(&name) {
                    if let Some(set) = syntax_set.as_deref_mut()
                        && let Ok(syntax) = set.load_by_reference(&name)
                    {
                        self.context_stack.push(ContextFrame::named_with_injected(
                            syntax,
                            "main".to_string(),
                            injected_patterns,
                            captures,
                            line,
                        ));
                        return Ok(());
                    }

                    // Best-effort fallback: unresolved external syntax.
                    let empty_ctx = CompiledContext {
                        meta_scope: Vec::new(),
                        meta_content_scope: Vec::new(),
                        include_prototype: false,
                        clear_scopes: None,
                        patterns: Vec::new(),
                        meta_prepend: false,
                        meta_append: false,
                    };
                    self.context_stack.push(ContextFrame::inline_with_injected(
                        self.root_syntax.clone(),
                        empty_ctx,
                        injected_patterns,
                        captures,
                        line,
                    ));
                    return Ok(());
                }

                let syntax = self.syntax_for_scope(&origin_scope, syntax_set)?;
                self.context_stack.push(ContextFrame::named_with_injected(
                    syntax,
                    name,
                    injected_patterns,
                    captures,
                    line,
                ));
                Ok(())
            }
            ContextSpec::Inline {
                origin_scope,
                context,
            } => {
                let syntax = self.syntax_for_scope(&origin_scope, syntax_set)?;
                self.context_stack.push(ContextFrame::inline_with_injected(
                    syntax,
                    context,
                    injected_patterns,
                    captures,
                    line,
                ));
                Ok(())
            }
        }
    }

    fn syntax_for_scope(
        &mut self,
        scope: &str,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Arc<SublimeSyntax>, SublimeSyntaxError> {
        if self.root_syntax.scope == scope {
            return Ok(self.root_syntax.clone());
        }
        let Some(set) = syntax_set.as_deref() else {
            return Err(SublimeSyntaxError::UnknownSyntaxReference(
                scope.to_string(),
            ));
        };
        set.get_by_scope(scope)
            .ok_or_else(|| SublimeSyntaxError::UnknownSyntaxReference(scope.to_string()))
    }

    fn pop_one_context(&mut self, line: usize) {
        if self.context_stack.len() <= 1 {
            return;
        }

        let frame = self.context_stack.pop().expect("len checked");
        let ctx = match frame.context() {
            Ok(c) => c,
            Err(_) => return,
        };

        if !ctx.meta_scope.is_empty() && line > frame.entered_at_line {
            self.fold_regions
                .push(FoldRegion::new(frame.entered_at_line, line));
        }
    }
}

#[derive(Debug, Clone)]
struct ContextFrame {
    syntax: Arc<SublimeSyntax>,
    context_name: String,
    is_inline: bool,
    inline_context: Option<CompiledContext>,
    injected_patterns: Vec<CompiledPattern>,
    captures: Arc<Vec<String>>,
    entered_at_line: usize,
}

impl ContextFrame {
    fn named(syntax: Arc<SublimeSyntax>, name: String, entered_at_line: usize) -> Self {
        Self {
            syntax,
            context_name: name,
            is_inline: false,
            inline_context: None,
            injected_patterns: Vec::new(),
            captures: Arc::new(Vec::new()),
            entered_at_line,
        }
    }

    fn named_with_injected(
        syntax: Arc<SublimeSyntax>,
        name: String,
        injected_patterns: Vec<CompiledPattern>,
        captures: Arc<Vec<String>>,
        entered_at_line: usize,
    ) -> Self {
        Self {
            syntax,
            context_name: name,
            is_inline: false,
            inline_context: None,
            injected_patterns,
            captures,
            entered_at_line,
        }
    }

    fn inline_with_injected(
        syntax: Arc<SublimeSyntax>,
        context: CompiledContext,
        injected_patterns: Vec<CompiledPattern>,
        captures: Arc<Vec<String>>,
        entered_at_line: usize,
    ) -> Self {
        Self {
            syntax,
            context_name: "<inline>".to_string(),
            is_inline: true,
            inline_context: Some(context),
            injected_patterns,
            captures,
            entered_at_line,
        }
    }

    fn context(&self) -> Result<&CompiledContext, SublimeSyntaxError> {
        if self.is_inline {
            return self
                .inline_context
                .as_ref()
                .ok_or(SublimeSyntaxError::MissingField("inline context"));
        }
        self.syntax
            .contexts
            .get(&self.context_name)
            .ok_or_else(|| SublimeSyntaxError::UnknownContext(self.context_name.clone()))
    }

    fn snapshot(&self) -> ContextFrameSnapshot {
        ContextFrameSnapshot {
            syntax: self.syntax.clone(),
            context_name: self.context_name.clone(),
            is_inline: self.is_inline,
            inline_context: self.inline_context.clone(),
            injected_patterns: self.injected_patterns.clone(),
        }
    }
}

#[derive(Debug, Clone)]
struct ContextFrameSnapshot {
    syntax: Arc<SublimeSyntax>,
    context_name: String,
    is_inline: bool,
    inline_context: Option<CompiledContext>,
    injected_patterns: Vec<CompiledPattern>,
}

impl ContextFrameSnapshot {
    fn context(&self) -> Result<&CompiledContext, SublimeSyntaxError> {
        if self.is_inline {
            return self
                .inline_context
                .as_ref()
                .ok_or(SublimeSyntaxError::MissingField("inline context"));
        }
        self.syntax
            .contexts
            .get(&self.context_name)
            .ok_or_else(|| SublimeSyntaxError::UnknownContext(self.context_name.clone()))
    }
}

#[derive(Debug)]
struct FoundMatch {
    start_byte: usize,
    end_byte: usize,
    capture_positions: Vec<Option<(usize, usize)>>,
    pattern: CompiledMatchPattern,
}

#[derive(Debug, Default)]
struct PatternCache {
    // Keyed by (syntax_scope, context_name)
    flat: HashMap<(String, String), Vec<CompiledMatchPattern>>,
}

impl PatternCache {
    fn flatten_named_context(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        context_name: &str,
        syntax_set: Option<&mut SublimeSyntaxSet>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let key = (syntax.scope.clone(), context_name.to_string());
        if let Some(cached) = self.flat.get(&key) {
            return Ok(cached.clone());
        }

        let mut visiting = HashSet::<(String, String)>::new();
        let patterns =
            self.flatten_named_context_inner(syntax, context_name, syntax_set, &mut visiting)?;
        self.flat.insert(key, patterns.clone());
        Ok(patterns)
    }

    fn flatten_named_context_inner(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        context_name: &str,
        mut syntax_set: Option<&mut SublimeSyntaxSet>,
        visiting: &mut HashSet<(String, String)>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let key = (syntax.scope.clone(), context_name.to_string());
        if !visiting.insert(key.clone()) {
            return Err(SublimeSyntaxError::Unsupported(
                "include cycle detected while expanding contexts",
            ));
        }

        let ctx = syntax
            .contexts
            .get(context_name)
            .ok_or_else(|| SublimeSyntaxError::UnknownContext(context_name.to_string()))?;

        let mut out = Vec::new();

        if ctx.include_prototype && syntax.prototype_exists && context_name != "prototype" {
            let proto = self.flatten_named_context_inner(
                syntax,
                "prototype",
                syntax_set.as_deref_mut(),
                visiting,
            )?;
            out.extend(proto);
        }

        for pattern in &ctx.patterns {
            match pattern {
                CompiledPattern::Match(m) => out.push(m.clone()),
                CompiledPattern::Include(i) => {
                    let target = i.include.as_str();
                    if is_external_syntax_reference(target) {
                        // Best-effort: ignore unresolved external syntaxes.
                        if let Some(set) = syntax_set.as_deref_mut()
                            && let Ok(other) = set.load_by_reference(target)
                        {
                            let other_patterns =
                                self.flatten_named_context(&other, "main", Some(set))?;
                            out.extend(other_patterns);
                        }
                    } else {
                        let included = self.flatten_named_context_inner(
                            syntax,
                            target,
                            syntax_set.as_deref_mut(),
                            visiting,
                        )?;
                        out.extend(included);
                    }
                }
            }
        }

        visiting.remove(&key);
        Ok(out)
    }
}

fn is_external_syntax_reference(name: &str) -> bool {
    name.starts_with("scope:")
        || name.starts_with("Packages/")
        || name.ends_with(".sublime-syntax")
        || name.contains("/Packages/")
}

fn search_first_region(
    regex: &Arc<Regex>,
    text: &str,
    from: usize,
) -> Result<Option<Region>, SublimeSyntaxError> {
    let mut region = Region::new();
    let len = text.len();
    let Some(_) = regex.search_with_options(
        text,
        from,
        len,
        SearchOptions::SEARCH_OPTION_NONE,
        Some(&mut region),
    ) else {
        return Ok(None);
    };

    Ok(Some(region))
}

fn extract_captures(line_text: &str, positions: &[Option<(usize, usize)>]) -> Vec<String> {
    positions
        .iter()
        .map(|pos| match pos {
            Some((start, end)) => line_text
                .get(*start..*end)
                .unwrap_or_default()
                .to_string(),
            None => String::new(),
        })
        .collect()
}

fn substitute_context_backrefs(source: &str, captures: &[String]) -> String {
    let mut out = String::with_capacity(source.len());

    let chars: Vec<char> = source.chars().collect();
    let mut i = 0usize;
    while i < chars.len() {
        let ch = chars[i];
        if ch != '\\' {
            out.push(ch);
            i += 1;
            continue;
        }

        // Count the run of backslashes.
        let start = i;
        while i < chars.len() && chars[i] == '\\' {
            i += 1;
        }
        let run_len = i - start;

        // If this is an odd-length run followed by a digit, treat the last '\' as a
        // context backref marker and substitute the digit from captured text.
        if i < chars.len() && chars[i].is_ascii_digit() && run_len % 2 == 1 {
            let digit = chars[i].to_digit(10).unwrap_or(0) as usize;

            for _ in 0..(run_len - 1) {
                out.push('\\');
            }

            let value = captures.get(digit).map(|s| s.as_str()).unwrap_or_default();
            out.push_str(&escape_onig_literal(value));
            i += 1; // consume digit
            continue;
        }

        for _ in 0..run_len {
            out.push('\\');
        }
    }

    out
}

fn escape_onig_literal(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        match ch {
            '\\' | '.' | '^' | '$' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '|'
            | '-' => {
                out.push('\\');
                out.push(ch);
            }
            _ => out.push(ch),
        }
    }
    out
}

#[derive(Debug, Clone, Copy)]
enum ScopeMode {
    Content,
    Match,
}

fn compute_scopes(
    frames: &[ContextFrame],
    mode: ScopeMode,
    match_scope: Option<&Vec<String>>,
    base_scope: &str,
) -> Vec<String> {
    let mut stack: Vec<String> = Vec::new();
    stack.push(base_scope.to_string());

    let top_idx = frames.len().saturating_sub(1);
    for (idx, frame) in frames.iter().enumerate() {
        let Ok(ctx) = frame.context() else {
            continue;
        };

        apply_clear_scopes(&mut stack, ctx);
        stack.extend(ctx.meta_scope.iter().cloned());

        let include_content_scopes = match mode {
            ScopeMode::Content => true,
            ScopeMode::Match => idx != top_idx,
        };
        if include_content_scopes {
            stack.extend(ctx.meta_content_scope.iter().cloned());
        }
    }

    if let (ScopeMode::Match, Some(scope)) = (mode, match_scope) {
        stack.extend(scope.iter().cloned());
    }

    stack
}

fn apply_clear_scopes(stack: &mut Vec<String>, ctx: &CompiledContext) {
    let Some(clear) = &ctx.clear_scopes else {
        return;
    };

    match clear {
        ClearScopes::Count(n) => {
            let n = (*n).min(stack.len());
            stack.truncate(stack.len().saturating_sub(n));
        }
        ClearScopes::All(true) => {
            stack.clear();
        }
        ClearScopes::All(false) => {}
    }
}
