///|
/// Small regex engine covering the constructs used by the five schemas:
/// anchors, literals, `.`, character classes with ranges/negation, escapes,
/// and the quantifiers `*`, `+`, `?`, `{m}`, `{m,}`, `{m,n}`.
enum RAtom {
  RLit(Char)
  RAny
  RCls(Bool, Array[(Char, Char)])
  RBol
  REol
}

///|
struct RTok {
  atom : RAtom
  min : Int
  max : Int // -1 means unbounded
}

///|
fn parse_class(chars : Array[Char], start : Int) -> (RAtom, Int) raise ContractError {
  // `chars[start]` is '['; returns (atom, index after ']').
  let mut idx = start + 1
  let mut negated = false
  if idx < chars.length() && chars[idx] == '^' {
    negated = true
    idx = idx + 1
  }
  let ranges : Array[(Char, Char)] = []
  let mut go = true
  while go {
    if idx >= chars.length() {
      raise ContractError("Unterminated character class in pattern")
    }
    let c = chars[idx]
    if c == ']' && ranges.length() > 0 || c == ']' && negated {
      go = false
      return (RCls(negated, ranges), idx + 1)
    }
    if c == ']' && ranges.length() == 0 && not(negated) {
      ranges.push((']', ']'))
      idx = idx + 1
    } else if c == '\\' && idx + 1 < chars.length() {
      ranges.push((chars[idx + 1], chars[idx + 1]))
      idx = idx + 2
    } else if idx + 2 < chars.length() && chars[idx + 1] == '-' && chars[idx + 2] != ']' {
      ranges.push((c, chars[idx + 2]))
      idx = idx + 3
    } else {
      ranges.push((c, c))
      idx = idx + 1
    }
  }
  raise ContractError("Unterminated character class in pattern")
}

///|
fn compile_regex(pattern : String) -> Array[RTok] raise ContractError {
  let chars = pattern.to_array()
  let toks : Array[RTok] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    let atom = if c == '^' {
      i = i + 1
      RBol
    } else if c == '$' {
      i = i + 1
      REol
    } else if c == '.' {
      i = i + 1
      RAny
    } else if c == '[' {
      let (atom, next) = parse_class(chars, i)
      i = next
      atom
    } else if c == '\\' && i + 1 < chars.length() {
      i = i + 2
      RLit(chars[i - 1])
    } else {
      i = i + 1
      RLit(c)
    }
    let mut min = 1
    let mut max = 1
    if i < chars.length() {
      let q = chars[i]
      if q == '*' {
        min = 0
        max = -1
        i = i + 1
      } else if q == '+' {
        min = 1
        max = -1
        i = i + 1
      } else if q == '?' {
        min = 0
        max = 1
        i = i + 1
      } else if q == '{' {
        let mut j = i + 1
        let mut lo = 0
        let mut has_lo = false
        while j < chars.length() && chars[j] >= '0' && chars[j] <= '9' {
          lo = lo * 10 + (chars[j].to_int() - '0'.to_int())
          has_lo = true
          j = j + 1
        }
        if has_lo {
          if j < chars.length() && chars[j] == '}' {
            min = lo
            max = lo
            i = j + 1
          } else if j < chars.length() && chars[j] == ',' {
            j = j + 1
            let mut hi = 0
            let mut has_hi = false
            while j < chars.length() && chars[j] >= '0' && chars[j] <= '9' {
              hi = hi * 10 + (chars[j].to_int() - '0'.to_int())
              has_hi = true
              j = j + 1
            }
            if j < chars.length() && chars[j] == '}' {
              min = lo
              max = if has_hi { hi } else { -1 }
              i = j + 1
            }
          }
        }
      }
    }
    toks.push({ atom, min, max })
  }
  toks
}

///|
fn atom_matches(atom : RAtom, text : Array[Char], ti : Int) -> Bool {
  match atom {
    RBol => ti == 0
    REol => ti == text.length()
    RLit(c) => ti < text.length() && text[ti] == c
    RAny => ti < text.length()
    RCls(neg, ranges) => {
      if ti >= text.length() {
        false
      } else {
        let c = text[ti]
        let mut inside = false
        for r in ranges {
          if c >= r.0 && c <= r.1 {
            inside = true
          }
        }
        if neg { not(inside) } else { inside }
      }
    }
  }
}

///|
fn match_repeat(
  toks : Array[RTok],
  si : Int,
  text : Array[Char],
  ti : Int,
  count : Int,
) -> Bool {
  let tok = toks[si]
  let upper = if tok.max < 0 { text.length() + 1 } else { tok.max }
  if count < upper && atom_matches(tok.atom, text, ti) {
    if match_repeat(toks, si, text, ti + 1, count + 1) {
      return true
    }
  }
  if count >= tok.min {
    return match_here(toks, si + 1, text, ti)
  }
  false
}

///|
fn match_here(toks : Array[RTok], si : Int, text : Array[Char], ti : Int) -> Bool {
  if si >= toks.length() {
    true
  } else {
    let tok = toks[si]
    match tok.atom {
      RBol =>
        if ti == 0 {
          match_here(toks, si + 1, text, ti)
        } else {
          false
        }
      REol =>
        if ti == text.length() {
          match_here(toks, si + 1, text, ti)
        } else {
          false
        }
      _ => match_repeat(toks, si, text, ti, 0)
    }
  }
}

///|
/// `re.search`-like semantics: the pattern may match anywhere unless anchored.
pub fn regex_search(pattern : String, text : String) -> Bool raise ContractError {
  let toks = compile_regex(pattern)
  let chars = text.to_array()
  let mut found = false
  for start = 0; start <= chars.length(); start = start + 1 {
    if not(found) && match_here(toks, 0, chars, start) {
      found = true
    }
  }
  found
}
