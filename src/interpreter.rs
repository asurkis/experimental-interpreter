use crate::parser::Tree;
use std::{collections::HashMap, hash::Hash};

#[derive(Debug, Clone, Default)]
struct Context<'a> {
    variables: HashMap<&'a str, i64>,
}

fn replace_or_remove<K: Eq + Hash + Copy, V>(map: &mut HashMap<K, V>, key: K, item: Option<V>) {
    match item {
        None => map.remove(&key),
        Some(val) => map.insert(key, val),
    };
}

fn interpret<'a>(ctx: &mut Context<'a>, tree: &'a Tree) -> Result<i64, String> {
    match tree {
        Tree::Atom(var) => ctx
            .variables
            .get(&var[..])
            .copied()
            .ok_or_else(|| format!("Unknown variable {var:?}")),
        Tree::Array(arr) => {
            if arr.len() < 2 {
                return Err(format!("Array of length {}", arr.len()));
            }
            match &arr[0] {
                Tree::Atom(s) => match &s[..] {
                    "+" => {
                        let mut acc = interpret(ctx, &arr[1])?;
                        for x in &arr[2..] {
                            acc = acc.wrapping_add(interpret(ctx, x)?);
                        }
                        Ok(acc)
                    }
                    "-" => {
                        let mut acc = interpret(ctx, &arr[1])?;
                        for x in &arr[2..] {
                            acc = acc.wrapping_sub(interpret(ctx, x)?);
                        }
                        Ok(acc)
                    }
                    "*" => {
                        let mut acc = interpret(ctx, &arr[1])?;
                        for x in &arr[2..] {
                            acc = acc.wrapping_mul(interpret(ctx, x)?);
                        }
                        Ok(acc)
                    }
                    "/" => {
                        let mut acc = interpret(ctx, &arr[1])?;
                        for x in &arr[2..] {
                            let y = interpret(ctx, x)?;
                            if y == 0 {
                                return Err("Division by zero".into());
                            }
                            acc /= y;
                        }
                        Ok(acc)
                    }
                    "let" => {
                        if arr.len() != 4 {
                            return Err("Variable binding must have variable name, value, and expression where the variable is used".into());
                        }
                        let Tree::Atom(var) = &arr[1] else {
                            return Err("Variable name must be an atom".into());
                        };
                        let val = interpret(ctx, &arr[2])?;
                        let old_val = ctx.variables.insert(&var[..], val);
                        let body = interpret(ctx, &arr[3]);
                        replace_or_remove(&mut ctx.variables, &var[..], old_val);
                        body
                    }
                    _ => Err(format!("Unknown function {s}")),
                },
                Tree::Array(_) => Err("Array used as function".into()),
                Tree::Int64(_) => Err("Number used as function".into()),
            }
        }
        &Tree::Int64(x) => Ok(x),
    }
}

pub fn parse_interpret(s: &str) -> Result<i64, String> {
    let mut ctx = Context::default();
    interpret(&mut ctx, &s.parse()?)
}
