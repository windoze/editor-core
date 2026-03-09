/// A small fuzzy matcher intended for “quick open” and command palette filtering.
///
/// Matching rule:
/// - case-insensitive subsequence match (`query` chars must appear in order in `candidate`)
/// - higher score is better
///
/// This intentionally mirrors the simple scoring used in the Swift AttoEditor prototype.
#[derive(Debug, Default, Clone, Copy)]
pub struct FuzzyMatcher;

impl FuzzyMatcher {
    /// Score a candidate string against a query.
    ///
    /// Returns `None` when `query` does not match `candidate` as a subsequence.
    pub fn score(candidate: &str, query: &str) -> Option<i32> {
        let query = query.trim();
        if query.is_empty() {
            return Some(0);
        }

        let candidate = candidate.to_lowercase();
        let query = query.to_lowercase();

        let candidate_chars: Vec<char> = candidate.chars().collect();
        let query_chars: Vec<char> = query.chars().collect();

        fn is_boundary(ch: char) -> bool {
            matches!(ch, '/' | '\\' | '_' | '-' | ' ' | '.')
        }

        let mut score: i32 = 0;
        let mut c_index: usize = 0;
        let mut consecutive: i32 = 0;
        let mut first_match: Option<usize> = None;

        for qc in query_chars {
            while c_index < candidate_chars.len() && candidate_chars[c_index] != qc {
                c_index = c_index.saturating_add(1);
                consecutive = 0;
            }

            if c_index >= candidate_chars.len() {
                return None;
            }

            if first_match.is_none() {
                first_match = Some(c_index);
            }

            score += 10;
            score += consecutive * 6;
            if c_index == 0 || is_boundary(candidate_chars[c_index.saturating_sub(1)]) {
                score += 4;
            }

            consecutive += 1;
            c_index = c_index.saturating_add(1);
        }

        if let Some(first) = first_match {
            score -= (first.min(20)) as i32;
        }

        Some(score)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fuzzy_empty_query_matches_everything() {
        assert_eq!(FuzzyMatcher::score("abc", ""), Some(0));
        assert_eq!(FuzzyMatcher::score("", ""), Some(0));
    }

    #[test]
    fn fuzzy_subsequence_match_is_case_insensitive() {
        assert!(FuzzyMatcher::score("HelloWorld", "hwd").is_some());
        assert!(FuzzyMatcher::score("HelloWorld", "HWD").is_some());
        assert!(FuzzyMatcher::score("HelloWorld", "x").is_none());
    }

    #[test]
    fn fuzzy_prefers_boundary_matches() {
        let a = FuzzyMatcher::score("src/main.rs", "mr").unwrap();
        let b = FuzzyMatcher::score("src/normal.rs", "mr").unwrap_or(-999);
        assert!(a > b);
    }
}
