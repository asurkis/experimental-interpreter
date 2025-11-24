use crate::parser::Value;

fn interpret(value: &Value) -> Result<i64, String> {
    match value {
        Value::Atom(_) => Err("Variables are not yet implemented".into()),
        Value::Array(arr) => {
            if arr.len() < 2 {
                Err(format!("Array of length {}", arr.len()))
            } else {
                match &arr[0] {
                    Value::Atom(s) => match &s[..] {
                        "+" => {
                            let mut acc = interpret(&arr[1])?;
                            for x in &arr[2..] {
                                acc = acc.wrapping_add(interpret(x)?);
                            }
                            Ok(acc)
                        }
                        "-" => {
                            let mut acc = interpret(&arr[1])?;
                            for x in &arr[2..] {
                                acc = acc.wrapping_sub(interpret(x)?);
                            }
                            Ok(acc)
                        }
                        "*" => {
                            let mut acc = interpret(&arr[1])?;
                            for x in &arr[2..] {
                                acc = acc.wrapping_mul(interpret(x)?);
                            }
                            Ok(acc)
                        }
                        "/" => {
                            let mut acc = interpret(&arr[1])?;
                            for x in &arr[2..] {
                                let y = interpret(x)?;
                                if y == 0 {
                                    return Err("Division by zero".into());
                                }
                                acc /= y;
                            }
                            Ok(acc)
                        }
                        _ => Err(format!("Unknown function {s}")),
                    },
                    Value::Array(_) => Err("Array used as function".into()),
                    Value::Int64(_) => Err("Number used as function".into()),
                }
            }
        }
        &Value::Int64(x) => Ok(x),
    }
}

pub fn parse_interpret(s: &str) -> Result<i64, String> {
    interpret(&s.parse()?)
}
