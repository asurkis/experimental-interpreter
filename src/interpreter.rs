use crate::parser::Tree;
use crate::util::replace_or_remove;
use crate::{guard, match_ok};
use std::collections::HashMap;

#[derive(Debug, Clone, Default)]
struct Context<'a> {
    variables: HashMap<&'a str, Value>,
}

#[derive(Debug, Clone)]
pub enum TypeInfo {
    Unit,
    Int64,
    Array(Box<TypeInfo>),
}

#[derive(Debug, Clone)]
pub enum Value {
    Unit,
    Int64(i64),
    Type(TypeInfo),
    Array(Vec<Value>),
}

impl TypeInfo {
    pub fn zero(&self) -> Value {
        match self {
            Self::Unit => Value::Unit,
            Self::Int64 => Value::Int64(0),
            Self::Array(_) => Value::Array(Vec::new()),
        }
    }
}

fn interpret<'a>(ctx: &mut Context<'a>, tree: &'a Tree) -> Result<Value, String> {
    match tree {
        Tree::Atom(var) => ctx
            .variables
            .get(&var[..])
            .cloned()
            .ok_or_else(|| format!("Unknown variable {var:?}")),
        Tree::Array(arr) => {
            guard!(!arr.is_empty());
            match &arr[0] {
                Tree::Atom(s) => match &s[..] {
                    "+" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            acc = acc.wrapping_add(y);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "-" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            acc = acc.wrapping_sub(y);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "*" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(y) => y)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            acc = acc.wrapping_mul(y);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "/" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(y) => y)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            guard!(y != 0);
                            acc /= y;
                        }
                        Ok(Value::Int64(acc))
                    }
                    "let" => {
                        guard!(arr.len() == 4);
                        let var = match_ok!(&arr[1], Tree::Atom(x) => x)?;
                        let val = interpret(ctx, &arr[2])?;
                        let old_val = ctx.variables.insert(var, val);
                        let body = interpret(ctx, &arr[3]);
                        replace_or_remove(&mut ctx.variables, var, old_val);
                        body
                    }
                    "var" => {
                        guard!(arr.len() == 4);
                        let var = match_ok!(&arr[1], Tree::Atom(x) => x)?;
                        let typ_val = interpret(ctx, &arr[2])?;
                        let typ = match_ok!(&typ_val, Value::Type(x) => x)?;
                        let old_val = ctx.variables.insert(var, typ.zero());
                        let body = interpret(ctx, &arr[3]);
                        replace_or_remove(&mut ctx.variables, var, old_val);
                        body
                    }
                    "seq" => {
                        let mut out = Value::Unit;
                        for x in &arr[1..] {
                            out = interpret(ctx, x)?;
                        }
                        Ok(out)
                    }
                    "set" => {
                        guard!(arr.len() == 3);
                        let var = match_ok!(&arr[1], Tree::Atom(x) => x)?;
                        let val = interpret(ctx, &arr[2])?;
                        let pos = ctx
                            .variables
                            .get_mut(&var[..])
                            .ok_or_else(|| format!("Undeclared variable {var:?}"))?;
                        *pos = val;
                        Ok(Value::Unit)
                    }
                    "array" => {
                        let mut out = Vec::new();
                        for x in &arr[1..] {
                            out.push(interpret(ctx, x)?);
                        }
                        Ok(Value::Array(out))
                    }
                    "array-t" => {
                        guard!(arr.len() == 2);
                        let inner = match_ok!(interpret(ctx, &arr[1])?, Value::Type(x) => x)?;
                        Ok(Value::Type(TypeInfo::Array(Box::new(inner))))
                    }
                    "array-get" => {
                        guard!(arr.len() == 3);
                        let index = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        let mut array = match_ok!(interpret(ctx, &arr[2])?, Value::Array(x) => x)?;
                        guard!(0 <= index && (index as usize) < array.len());
                        Ok(array.swap_remove(index as usize))
                    }
                    "array-set" => {
                        guard!(arr.len() == 4);
                        let val = interpret(ctx, &arr[3])?;
                        let index = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        let var = match_ok!(&arr[2], Tree::Atom(x) => x)?;
                        let array_mut_val = ctx
                            .variables
                            .get_mut(&var[..])
                            .ok_or_else(|| format!("Array {var:?} not found"))?;
                        let array_mut = match_ok!(array_mut_val, Value::Array(x) => x)?;
                        guard!(0 <= index && (index as usize) < array_mut.len());
                        array_mut[index as usize] = val;
                        Ok(Value::Unit)
                    }
                    _ => Err(format!("Unknown function {s}")),
                },
                Tree::Array(_) => Err("Array used as function".into()),
                Tree::Int64(_) => Err("Number used as function".into()),
            }
        }
        &Tree::Int64(x) => Ok(Value::Int64(x)),
    }
}

pub fn parse_interpret(s: &str) -> Result<Value, String> {
    let mut ctx = Context::default();
    ctx.variables.insert("i64", Value::Type(TypeInfo::Int64));
    interpret(&mut ctx, &s.parse()?)
}
