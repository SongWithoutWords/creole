{-# language OverloadedStrings #-}

module CodeGen(codeGen) where

import qualified Data.Map as M
import Data.String
import Control.Monad.State(gets)

import qualified LLVM.AST as A
import qualified LLVM.AST.Constant as C
import qualified LLVM.AST.Global as G
import qualified LLVM.AST.Type as T

import Ast.A3Typed
import CodeGen.Instructions
import CodeGen.CodeGenM
import CodeGen.Util
import Util.MultiMap

codeGen :: Ast -> A.Module
codeGen ast = A.defaultModule
  { A.moduleName = "pidgin!"
  , A.moduleDefinitions = multiMapFoldWithKey genUnit ast
  }

genUnit :: String -> Unit -> A.Definition
genUnit name unit = A.GlobalDefinition $ case unit of

  -- Although I think purity could be discarded earlier in compilation, it may help
  -- with validating some optimizations
  UFunc (Func (Sig purity params retType) block) -> G.functionDefaults
    { G.name = A.Name $ fromString name
    , G.parameters = let vaArgs = False in (genParams params, vaArgs)
    , G.returnType = typeToLlvmType retType
    , G.basicBlocks = genBlock params block
    }

genParams :: Params -> [G.Parameter]
genParams params = map genParam params
  where
    genParam :: Param -> G.Parameter
    genParam (Named name t) = G.Parameter (typeToLlvmType t) (fromString name) []

genBlock :: Params -> Block -> [G.BasicBlock]
genBlock params block = buildBlocksFromCodeGenM $ genBlock' params block

genBlock' :: Params -> Block -> CodeGenM ()
genBlock' params (Block stmts retExpr) = do
  entryBlockName <- addBlock "entry"
  setBlock entryBlockName
  mapM_ addParamBinding params
  mapM_ genStmt stmts

  retOp <- mapM genExpr retExpr
  setTerminator $ A.Do $ A.Ret retOp []

  where
    addParamBinding (Named name t) = addLocalBinding name t

genStmt :: Stmt -> CodeGenM ()
genStmt stmt = case stmt of

  SVar (Named name (Var _ e)) -> do
    oper <- genExpr e
    addBinding name oper

intWidth = 64

-- Generates intermediate computations + returns a reference to the operand of the result
genExpr :: Expr -> CodeGenM A.Operand
genExpr (Expr typ expr) = case expr of

  EApp (App e (Args _ args)) -> do

    let retType = case typ of
          TFunc _ _ ret -> ret
          _ -> error "CodeGen received EApp with non applicable type"

    e' <- genExpr e
    args' <- traverse genExpr args
    call (typeToLlvmType retType) e' args'

  EName n -> do
    locals <- gets bindings
    return $ if M.member n locals
      then localReference n typ
      else globalReference n typ

  EIf (Cond ec) e1 e2 -> do
    ifTrue <- addBlock "if.true"
    ifFalse <- addBlock "if.false"
    ifEnd <- addBlock "if.end"

    cond <- genExpr ec
    condBr cond ifTrue ifFalse

    setBlock ifTrue
    e1' <- genExpr e1
    br ifEnd

    setBlock ifFalse
    e2' <- genExpr e2
    br ifEnd

    setBlock ifEnd
    phi (typeToLlvmType typ) [(e1', ifTrue), (e2', ifFalse)]

  EUnOp op a@(Expr ta _) -> let

    genUnOp :: UnOp -> Type -> A.Operand -> CodeGenM A.Operand

    genUnOp Neg TInt = imul intWidth (A.ConstantOperand $ C.Int intWidth (-1))

    in do
      a' <- genExpr a
      genUnOp op ta a'


  EBinOp op e1@(Expr t1 _) e2@(Expr t2 _) -> let

    genBinOp :: BinOp -> Type -> Type -> A.Operand -> A.Operand -> CodeGenM A.Operand

    genBinOp Add TInt TInt = iadd intWidth
    genBinOp Sub TInt TInt = isub intWidth
    genBinOp Mul TInt TInt = imul intWidth
    genBinOp Div TInt TInt = sdiv intWidth

    genBinOp Mod TInt TInt = genMod
      where
        genMod a b = do
          -- Mathematically correct modulus, a mod b,
          -- implemented as ((a rem b) + b) rem b
          aRemB <- srem intWidth a b
          aRemBPlusB <- iadd intWidth aRemB b
          srem intWidth aRemBPlusB b

    genBinOp (Cmp Greater) TInt TInt = igreater
    genBinOp (Cmp Lesser) TInt TInt = ilesser
    genBinOp (Cmp GreaterEq) TInt TInt = igreaterEq
    genBinOp (Cmp LesserEq) TInt TInt = ilesserEq

    genBinOp (Cmp Equal) TInt TInt = iequal
    genBinOp (Cmp NotEqual) TInt TInt = inotEqual

    genBinOp Add TFlt TFlt = fadd T.FloatFP

    genBinOp oper ta tb = error $
      "genBinOp " ++ show oper ++ " " ++ show ta ++ " " ++ show tb

    in do
      e1' <- genExpr e1
      e2' <- genExpr e2
      genBinOp op t1 t2 e1' e2'

  EVal v -> case v of
    VBln b -> return $ A.ConstantOperand $ C.Int 1 $ case b of True -> 1; False -> 0
    VInt i -> return $ A.ConstantOperand $ C.Int intWidth $ toInteger i

