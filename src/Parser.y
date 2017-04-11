{
module Parser where
import Ast
import ParseError
import qualified Tokens as T
}

%name parse
%tokentype { T.Token }
%error { parseError }

%token
  eol           { T.Eol }

  ind           { T.Indent }
  ded           { T.Dedent }

  Bln           { T.TypeBln }
  Chr           { T.TypeChr }
  Flt           { T.TypeFlt }
  Int           { T.TypeInt }
  Nat           { T.TypeNat }
  None          { T.TypeNone }
  Str           { T.TypeStr }
  This          { T.TypeThis }

  if            { T.If }
  else          { T.Else }
  true          { T.True }
  false         { T.False }
  and           { T.And }
  or            { T.Or }
  not           { T.Not }
  none          { T.None }

  tknNamespace  { T.Namespace }
  tknClass      { T.Class }

  pub           { T.Pub }
  pro           { T.Pro }
  pri           { T.Pri }

  "~"           { T.Tilde }
  "@"           { T.At }
  "#"           { T.Hash }
  "$"           { T.Dollar }
  "^"           { T.Caret }
  "&"           { T.Ampersand }
  "*"           { T.Star }
  "("           { T.LParen }
  ")"           { T.RParen }
  "-"           { T.Minus }
  "+"           { T.Plus }
  "="           { T.Equal }
  "["           { T.LBracket }
  "]"           { T.RBracket }
  ";"           { T.Semicolon}
  ":"           { T.Colon }
  ","           { T.Comma }
  "."           { T.Dot }
  "?"           { T.QMark }

  "<"           { T.Lesser }
  ">"           { T.Greater }
  "<="          { T.LesserEq }
  ">="          { T.GreaterEq}

  "->"          { T.ThinArrow }
  "=>"          { T.FatArrow }

  litChr        { T.LitChr $$ }
  litFlt        { T.LitFlt $$ }
  litInt        { T.LitInt $$ }
  litStr        { T.LitStr $$ }

  name          { T.Name $$ }
  typename      { T.Typename $$ }

%%

-- If performance becomes a concern will need to parse sequences another way
-- (see Happy docs)

root : unitsOrNone { $1 }

indentedUnits
  : {- none -}    { [] }
  | ind units ded { $2 } 

unitsOrNone
  : {- none -}    { [] }
  | units         { $1 }

units
  : unit            { [$1] }
  | unit eol units  { $1 : $3}

unit
  : namespace       { $1 }
  | class           { UClass $1 }
  | function        { UFunc $1 }
  | variable        { UVar $1 }

namespace
  : tknNamespace name indentedUnits { UNamespace $2 $3 }

class
  : tknClass typename indentedMembers  { Class $2 $3 } 

indentedMembers
  : {- none -}      { [] }
  | ind members ded { $2 }

members
  : member              { [$1] }
  | member eol members  { $1 : $3 }

member
  : accessMod class                                   { MClass $1 $2 }
  | accessMod mut function                            { MFunc $1 $2 $3 }
  | accessMod purity This parameterList indentedBlock { MCons $1 $2 $4 $5 }
  | accessMod variable                                { MVar $1 $2}

accessMod
  : pub   { Pub }  
  | pro   { Pro }
  | pri   { Pri }

paramTypes
  : "("")"          { [] } -- '()' must be implemented differently than for parameters/expressions to avoid reduce/reduce conflict
  | "(" typesCS ")" { $2 }

typesCS
  : type              { [$1] }
  | type "," typesCS  { $1 : $3 }

type
  : mut typename                { TUser $1 $2 }
  | purity paramTypes "->" type { TFunc $1 $2 $4 }
  | mut "$"                     { TInferred $1 }
  | mut "^" type                { TTempRef $1 $3 }
  | mut "&" type                { TPersRef $1 $3 }
  | mut "?" type                { TOption $1 $3 }
  | "*" type                    { TZeroPlus $2 }
  | "+" type                    { TOnePlus $2 }

  | mut Bln                     { TBln $1 }
  | mut Chr                     { TChr $1 }
  | mut Flt                     { TFlt $1 }
  | mut Int                     { TInt $1 }
  | mut Nat                     { TNat $1 }
  | None                        { TNone }
  | mut Str                     { TStr $1 }
  

  -- | mutability prim             { TPrim $1 $2 }

-- prim
  -- : Bln { PrimBln }
  -- | Chr { PrimChr }
  -- | Flt { PrimFlt }
  -- | Int { PrimInt }
  -- | Nat { PrimNat }
  -- | Str { PrimStr } 

mut
  : {- none -} { Immutable }
  | "~"        { Mutable }


block
  : indentedBlock { $1 }
  | inlineBlock   { $1 }

indentedBlock
  : ind subBlocks ded { $2 }

subBlocks
  : subBlock                  { $1 }
  | subBlock eol subBlocks    { $1 ++ $3 }

subBlock
  : inlineBlock                 { $1 }
  | nestedBlock                 { [$1] }

inlineBlock
  : stmt                  { [$1] }
  | stmt ";" inlineBlock  { $1 : $3 }

nestedBlock
  : function        { SFunc $1 }
  | ifChain         { SIf $1 }

stmt
  : lexpr "=" expr  { SAssign $1 $3 }
  | variable        { SVar $1 }
  -- | apply           { SApply $1 }
  | expr            { SExpr $1 }

lexpr
  : apply           { LApply $1 }
  | select          { LSelect $1 }
  | name            { LName $1 }

variable
  : typedName "=" expr { Var $1 $3 }

function
  : signature "=>" block { Func $1 $3 }

signature
  : purity name parameterList "->" type { Sig $2 $ AnonSig $1 $3 $5 }

purity
  : {- none -} { Pure }
  | "@"        { Impure }
  | "~""@"     { SideEffecting }


parameterList
  : "(" parametersCS ")"  { $2 }

parametersCS
  : {- none -}                  { [] }
  | typedName                   { [$1] }
  | typedName "," parametersCS  { $1 : $3 }

typedName
  : type name { TypedName $1 $2 }

exprsCS
  : {- none -}        { [] }
  | expr              { [$1]}
  | expr "," exprsCS  { $1 : $3 } -- also causing conficts. Hmm...

expr
  : expr if shallowExpr else expr         { EIf $1 $3 $5 }
  | lambda      { ELambda $1 }
  | shallowExpr { $1 }

 
-- lit

shallowExpr
  : apply     { EApply $1 }
  | construct { ECons $1 }
  | select    { ESelect $1 }
  | name      { EName $1 }
  | op        { $1 }
  -- | lit       { ELit $1 }

  | litBln {ELitBln $1}
  | litChr {ELitChr $1}
  | litFlt {ELitFlt $1}
  | litInt {ELitInt $1}
  | litStr {ELitStr $1}


ifChain
  : if condBlock                    { IfChainIf $2 IfChainNone }
  | if condBlock else ifChain       { IfChainIf $2 $4 }
  | if condBlock else indentedBlock { IfChainIf $2 $ IfChainElse $4 }

condBlock
  : expr indentedBlock  { CondBlock $1 $2 } -- Would be nice to have one-line ifs


-- ifExpr
  -- : expr if shallowExpr else expr { $1 $3 $5 }
  -- | expr if expr else

lambda
  : purity parameterList optionRet "=>"  indentedBlock { Lambda (AnonSig $1 $2 $3) $5 }
  -- : purity parameterList optionRet "=>"  block { Lambda (AnonSig $1 $2 $3) $5 }

optionRet
  : {- none -} { TInferred Mutable }
  | "->" type  { $2 }

apply
  : expr "(" exprsCS ")"  { Apply $1 $3 }

construct
  : typename "(" exprsCS ")" { Cons $1 $3 }

select
  : expr "." name { Select $1 $3 }

op
  : expr operator expr { EApply $ Apply (ESelect $ Select $1 $2) [$3] }

-- This is ridiculous, come up with some rules in the lexer if this is how it's going to be
operator 
  : "+"   { "+" }
  | "-"   { "-" }
  | "*"   { "*" }
  | ">"   { ">" }
  | "<"   { "<" }
  | ">="  { ">=" }
  | "<="  { "<=" }

-- lit
--   : litBln {LBln $1}
--   | litChr {LChr $1}
--   | litFlt {LFlt $1}
--   | litInt {LInt $1}
--   | litStr {LStr $1}

litBln
  : true  {True}
  | false {False}

