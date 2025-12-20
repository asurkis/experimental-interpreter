use crate::{guard, match_ok, token_tree::Tree};
use std::fmt::Write;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ArithmeticOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Tree2 {
    Ident(String),
    LetVal(String, Box<Tree2>, Box<Tree2>),
    LetType(String, Box<Tree2>, Box<Tree2>),
    Seq(Vec<Tree2>),
    Set(String, Box<Tree2>),
    LiteralInt64(i64),
    LiteralArray(Vec<Tree2>),
    LiteralArrayType(Box<Tree2>),
    Arithmetic(ArithmeticOp, Vec<Tree2>),
    ArrayGet(Box<Tree2>, Box<Tree2>),
    ArraySet(Box<Tree2>, Box<Tree2>, Box<Tree2>),
}

fn into_tree2(error_log: &mut String, tree1: &Tree) -> Option<Tree2> {
    match tree1 {
        Tree::Atom(x) => Some(Tree2::Ident(x.clone())),
        Tree::Array(subtree) => {
            guard!(error_log, !subtree.is_empty());
            let head = match_ok!(error_log, &subtree[0], Tree::Atom(x) => x)?;
            match &head[..] {
                "let" => {
                    guard!(error_log, subtree.len() == 4);
                    let var_res = into_tree2(error_log, &subtree[1]);
                    let val_res = into_tree2(error_log, &subtree[2]);
                    let body_res = into_tree2(error_log, &subtree[3]);
                    let var_opt = match_ok!(error_log, var_res, Some(Tree2::Ident(x)) => x);
                    let val_opt = match_ok!(error_log, val_res, Some(x) => x);
                    let body_opt = match_ok!(error_log, body_res, Some(x) => x);
                    Some(Tree2::LetVal(
                        var_opt?,
                        Box::new(val_opt?),
                        Box::new(body_opt?),
                    ))
                }
                "var" => {
                    guard!(error_log, subtree.len() == 4);
                    let var_res = into_tree2(error_log, &subtree[1]);
                    let type_res = into_tree2(error_log, &subtree[2]);
                    let body_res = into_tree2(error_log, &subtree[3]);
                    let var_opt = match_ok!(error_log, var_res, Some(Tree2::Ident(x)) => x);
                    let type_opt = match_ok!(error_log, type_res, Some(x) => x);
                    let body_opt = match_ok!(error_log, body_res, Some(x) => x);
                    Some(Tree2::LetType(
                        var_opt?,
                        Box::new(type_opt?),
                        Box::new(body_opt?),
                    ))
                }
                "seq" => {
                    guard!(error_log, subtree.len() > 1);
                    let mut out_opt = Some(Vec::new());
                    for subtree_it in &subtree[1..] {
                        let item_opt = into_tree2(error_log, subtree_it);
                        match (&mut out_opt, item_opt) {
                            (Some(out), Some(item)) => out.push(item),
                            _ => out_opt = None,
                        }
                    }
                    Some(Tree2::Seq(out_opt?))
                }
                "set" => {
                    guard!(error_log, subtree.len() == 3);
                    let var_res = into_tree2(error_log, &subtree[1]);
                    let val_opt = into_tree2(error_log, &subtree[2]);
                    let var_opt = match_ok!(error_log, var_res, Some(Tree2::Ident(x)) => x);
                    Some(Tree2::Set(var_opt?, Box::new(val_opt?)))
                }
                "array" => {
                    let mut out_opt = Some(Vec::new());
                    for subtree_it in &subtree[1..] {
                        let item_opt = into_tree2(error_log, subtree_it);
                        match (&mut out_opt, item_opt) {
                            (Some(out), Some(item)) => out.push(item),
                            _ => out_opt = None,
                        }
                    }
                    Some(Tree2::LiteralArray(out_opt?))
                }
                "array-t" => {
                    guard!(error_log, subtree.len() == 2);
                    let inner_opt = into_tree2(error_log, &subtree[1]);
                    Some(Tree2::LiteralArrayType(Box::new(inner_opt?)))
                }
                "+" | "-" | "*" | "/" | "%" => {
                    let op = match &head[..] {
                        "+" => ArithmeticOp::Add,
                        "-" => ArithmeticOp::Sub,
                        "*" => ArithmeticOp::Mul,
                        "/" => ArithmeticOp::Div,
                        "%" => ArithmeticOp::Rem,
                        _ => return None,
                    };
                    let mut out_opt = Some(Vec::new());
                    for subtree_it in &subtree[1..] {
                        let item_opt = into_tree2(error_log, subtree_it);
                        match (&mut out_opt, item_opt) {
                            (Some(out), Some(item)) => out.push(item),
                            _ => out_opt = None,
                        }
                    }
                    Some(Tree2::Arithmetic(op, out_opt?))
                }
                "array-get" => {
                    guard!(error_log, subtree.len() == 3);
                    let array_opt = into_tree2(error_log, &subtree[1]);
                    let index_opt = into_tree2(error_log, &subtree[2]);
                    Some(Tree2::ArrayGet(Box::new(array_opt?), Box::new(index_opt?)))
                }
                "array-set" => {
                    guard!(error_log, subtree.len() == 4);
                    let array_opt = into_tree2(error_log, &subtree[1]);
                    let index_opt = into_tree2(error_log, &subtree[2]);
                    let val_opt = into_tree2(error_log, &subtree[3]);
                    Some(Tree2::ArraySet(
                        Box::new(array_opt?),
                        Box::new(index_opt?),
                        Box::new(val_opt?),
                    ))
                }
                _ => {
                    writeln!(error_log, "Unknown head {head:?}").unwrap();
                    None
                }
            }
        }
        Tree::Int64(x) => Some(Tree2::LiteralInt64(*x)),
    }
}

impl TryFrom<&Tree> for Tree2 {
    type Error = String;
    fn try_from(value: &Tree) -> Result<Self, Self::Error> {
        let mut error_log = String::new();
        let tree2 = into_tree2(&mut error_log, value);
        tree2.ok_or(error_log)
    }
}
