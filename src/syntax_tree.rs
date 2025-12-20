use crate::{guard, match_ok, token_tree::TokenTree};
use std::{fmt::Write, rc::Rc};

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ArithmeticOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum SyntaxTree {
    Ident(Rc<str>),
    LetVal(Rc<str>, Box<SyntaxTree>, Box<SyntaxTree>),
    LetType(Rc<str>, Box<SyntaxTree>, Box<SyntaxTree>),
    Seq(Vec<SyntaxTree>),
    Set(Rc<str>, Box<SyntaxTree>),
    LiteralInt64(i64),
    LiteralArray(Vec<SyntaxTree>),
    LiteralArrayType(Box<SyntaxTree>),
    Arithmetic(ArithmeticOp, Vec<SyntaxTree>),
    ArrayGet(Box<SyntaxTree>, Box<SyntaxTree>),
    ArraySet(Box<SyntaxTree>, Box<SyntaxTree>, Box<SyntaxTree>),
}

fn into_syntax_tree(error_log: &mut String, tree1: &TokenTree) -> Option<SyntaxTree> {
    match tree1 {
        TokenTree::Atom(x) => Some(SyntaxTree::Ident(x.clone())),
        TokenTree::Array(subtree) => {
            guard!(error_log, !subtree.is_empty());
            let head = match_ok!(error_log, &subtree[0], TokenTree::Atom(x) => x)?;
            match &head[..] {
                "let" => {
                    guard!(error_log, subtree.len() == 4);
                    let var_res = into_syntax_tree(error_log, &subtree[1]);
                    let val_res = into_syntax_tree(error_log, &subtree[2]);
                    let body_res = into_syntax_tree(error_log, &subtree[3]);
                    let var_opt = match_ok!(error_log, var_res, Some(SyntaxTree::Ident(x)) => x);
                    let val_opt = match_ok!(error_log, val_res, Some(x) => x);
                    let body_opt = match_ok!(error_log, body_res, Some(x) => x);
                    Some(SyntaxTree::LetVal(
                        var_opt?,
                        Box::new(val_opt?),
                        Box::new(body_opt?),
                    ))
                }
                "var" => {
                    guard!(error_log, subtree.len() == 4);
                    let var_res = into_syntax_tree(error_log, &subtree[1]);
                    let type_res = into_syntax_tree(error_log, &subtree[2]);
                    let body_res = into_syntax_tree(error_log, &subtree[3]);
                    let var_opt = match_ok!(error_log, var_res, Some(SyntaxTree::Ident(x)) => x);
                    let type_opt = match_ok!(error_log, type_res, Some(x) => x);
                    let body_opt = match_ok!(error_log, body_res, Some(x) => x);
                    Some(SyntaxTree::LetType(
                        var_opt?,
                        Box::new(type_opt?),
                        Box::new(body_opt?),
                    ))
                }
                "seq" => {
                    guard!(error_log, subtree.len() > 1);
                    let mut out_opt = Some(Vec::new());
                    for subtree_it in &subtree[1..] {
                        let item_opt = into_syntax_tree(error_log, subtree_it);
                        match (&mut out_opt, item_opt) {
                            (Some(out), Some(item)) => out.push(item),
                            _ => out_opt = None,
                        }
                    }
                    Some(SyntaxTree::Seq(out_opt?))
                }
                "set" => {
                    guard!(error_log, subtree.len() == 3);
                    let var_res = into_syntax_tree(error_log, &subtree[1]);
                    let val_opt = into_syntax_tree(error_log, &subtree[2]);
                    let var_opt = match_ok!(error_log, var_res, Some(SyntaxTree::Ident(x)) => x);
                    Some(SyntaxTree::Set(var_opt?, Box::new(val_opt?)))
                }
                "array" => {
                    let mut out_opt = Some(Vec::new());
                    for subtree_it in &subtree[1..] {
                        let item_opt = into_syntax_tree(error_log, subtree_it);
                        match (&mut out_opt, item_opt) {
                            (Some(out), Some(item)) => out.push(item),
                            _ => out_opt = None,
                        }
                    }
                    Some(SyntaxTree::LiteralArray(out_opt?))
                }
                "array-t" => {
                    guard!(error_log, subtree.len() == 2);
                    let inner_opt = into_syntax_tree(error_log, &subtree[1]);
                    Some(SyntaxTree::LiteralArrayType(Box::new(inner_opt?)))
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
                        let item_opt = into_syntax_tree(error_log, subtree_it);
                        match (&mut out_opt, item_opt) {
                            (Some(out), Some(item)) => out.push(item),
                            _ => out_opt = None,
                        }
                    }
                    Some(SyntaxTree::Arithmetic(op, out_opt?))
                }
                "array-get" => {
                    guard!(error_log, subtree.len() == 3);
                    let array_opt = into_syntax_tree(error_log, &subtree[1]);
                    let index_opt = into_syntax_tree(error_log, &subtree[2]);
                    Some(SyntaxTree::ArrayGet(Box::new(array_opt?), Box::new(index_opt?)))
                }
                "array-set" => {
                    guard!(error_log, subtree.len() == 4);
                    let array_opt = into_syntax_tree(error_log, &subtree[1]);
                    let index_opt = into_syntax_tree(error_log, &subtree[2]);
                    let val_opt = into_syntax_tree(error_log, &subtree[3]);
                    Some(SyntaxTree::ArraySet(
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
        TokenTree::Int64(x) => Some(SyntaxTree::LiteralInt64(*x)),
    }
}

impl TryFrom<&TokenTree> for SyntaxTree {
    type Error = String;
    fn try_from(value: &TokenTree) -> Result<Self, Self::Error> {
        let mut error_log = String::new();
        let tree2 = into_syntax_tree(&mut error_log, value);
        tree2.ok_or(error_log)
    }
}
