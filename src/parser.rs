use std::fmt::Write;
use std::iter::Peekable;
use std::str::FromStr;

#[derive(Debug, Clone)]
pub enum Value {
    Atom(String),
    Array(Vec<Value>),
    Int64(i64),
}

fn skip_whitespace(iter: &mut Peekable<impl Iterator<Item = (usize, usize, char)>>) {
    while iter.next_if(|(_, _, c)| c.is_whitespace()).is_some() {}
}

fn is_word_delimiter(c: char) -> bool {
    c.is_whitespace() || c == '(' || c == ')'
}

fn next_word(iter: &mut Peekable<impl Iterator<Item = (usize, usize, char)>>) -> String {
    skip_whitespace(iter);
    let mut out = String::new();
    while let Some((_, _, c)) = iter.next_if(|&(_, _, c)| !is_word_delimiter(c)) {
        out.push(c);
    }
    out
}

fn parse_array(
    err_log: &mut String,
    iter: &mut Peekable<impl Iterator<Item = (usize, usize, char)>>,
) -> Option<Vec<Value>> {
    let Some((line1, col1, '(')) = iter.next() else {
        panic!()
    };
    let mut out = Some(Vec::new());
    loop {
        skip_whitespace(iter);
        match iter.peek() {
            None => {
                writeln!(err_log, "Unexpected EOF").unwrap();
                writeln!(err_log, "Unbalanced bracket at {line1}:{col1}").unwrap();
                return None;
            }
            Some((_, _, ')')) => {
                iter.next();
                return out;
            }
            Some(_) => match parse_value(err_log, iter) {
                None => out = None,
                Some(x) => {
                    if let Some(out1) = out.as_mut() {
                        out1.push(x)
                    }
                }
            },
        }
    }
}

fn parse_value(
    err_log: &mut String,
    iter: &mut Peekable<impl Iterator<Item = (usize, usize, char)>>,
) -> Option<Value> {
    match iter.peek() {
        None => {
            writeln!(err_log, "Unexpected EOF").unwrap();
            None
        }
        Some((line, col, ')')) => {
            writeln!(err_log, "Unbalanced bracket at {line}:{col}").unwrap();
            None
        }
        Some((_, _, '(')) => parse_array(err_log, iter).map(Value::Array),
        Some(_) => {
            let word = next_word(iter);
            if let Ok(x) = word.parse::<i64>() {
                Some(Value::Int64(x))
            } else {
                Some(Value::Atom(word))
            }
        }
    }
}

impl FromStr for Value {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let mut iter = s
            .split_inclusive('\n')
            .enumerate()
            .flat_map(|(line, s)| s.char_indices().map(move |(col, c)| (line + 1, col + 1, c)))
            .peekable();
        skip_whitespace(&mut iter);
        let mut err_log = String::new();
        match parse_value(&mut err_log, &mut iter) {
            None => Err(err_log),
            Some(x) => Ok(x),
        }
    }
}
