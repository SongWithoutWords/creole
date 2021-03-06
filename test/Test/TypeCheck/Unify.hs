module Test.TypeCheck.Unify(tests) where

import Data.Set as S
import Data.Map as M

import Test.Tasty
import Test.Tasty.HUnit

import Ast.A2Constrained
import TypeCheck.Unify

type SubstitutionList = [(TVar, Type)]

unifyTest :: String -> [Constraint] -> SubstitutionList -> [Error] -> TestTree
unifyTest name constraints subs errors =
  let (subsActual, errorsActual) = unify constraints
  in testGroup name
    [ testCase "substitutions" $ subsActual @?= M.fromList subs
    , testCase "errors" $ errorsActual @?= S.fromList errors
    ]

matchTest :: String -> MatchType -> Type -> Type -> Match -> TestTree
matchTest name mt t1 t2 expected =
  let result = match mt t1 t2
  in testCase name $ result @?= expected

tests :: TestTree
tests = testGroup "unify"
  [ unifyTest "empty" [] [] []

  , unifyTest "single"
    [TVar 0 :$= TInt]
    [(0, TInt)]
    []

  , unifyTest "assignment to mutable"
    [TMut (TVar 0) :$= TInt]
    [(0, TInt)]
    []

  , unifyTest "simple sub"
    [TVar 0 :$= TVar 1, TVar 1 :$= TInt]
    [(0, TInt), (1, TInt)]
    []

  , unifyTest "multiple subs"
    [TVar 0 :$= TVar 1, TVar 1 :$= TVar 2, TVar 2 :$= TInt]
    [(0, TInt), (1, TInt), (2, TInt)]
    []

  , unifyTest "lambda"
    [TVar 0 :$= [TVar 1] ~> (TVar 2), TVar 1 :$= TVar 2, TVar 2 :$= TInt]
    [(0, [TInt] ~> TInt), (1, TInt), (2, TInt)]
    []

  , unifyTest "overload-ish"
    [([TInt, TInt] ~> TVar 0) :$= TOver 1 [[TInt, TInt] ~> TInt]]
    [(0, TInt), (1, [TInt, TInt] ~> TInt)]
    []

  , unifyTest "simple overload"
    [ ([TInt, TInt] ~> TVar 0) :$= TOver 1
     [ [TInt, TInt] ~> TInt
     , [TFlt, TFlt] ~> TFlt]]
    [(0, TInt), (1, [TInt, TInt] ~> TInt)]
    []

  , unifyTest "overload selection with subtyping"
    [ ([TInt, TFlt] ~> TVar 0) :$= TOver 1
      [ [TInt, TInt] ~> TInt
      , [TFlt, TFlt] ~> TFlt]
    ]
    [(0, TFlt), (1, [TFlt, TFlt] ~> TFlt)]
    []

  , unifyTest "equally viable overload 1"
    [ TVar 0 :$= TOver 1 [TBln, TFlt] ]
    []
    [EquallyViableOverloads (TVar 0) $ S.fromList [TBln, TFlt]]

  , unifyTest "array construction"
    [([TInt, TInt] ~> TVar 0) :$= [TInt, TVar 1] ~> TArray $ TVar 1]
    [(0, TArray TInt), (1, TInt)]
    []

  , unifyTest "mutable array construction"
    [([TInt, TBln] ~> TMut $ TVar 0) :$= [TInt, TVar 1] ~> (TArray $ TVar 1)]
    [(0, TArray TBln), (1, TBln)]
    []

  , unifyTest "array access"
    [([TArray TInt, TInt] ~> TVar 0) :$= [TArray $ TVar 1, TInt] ~> (TVar 1)]
    [(0, TInt), (1, TInt)]
    []

  , unifyTest "array-app-overload-imt"
    [([TArray TBln, TInt] ~> TVar 0) :$= TOver 1
     [ [TRef $ TArray $ TVar 2, TInt] ~> TRef $ TVar 2
     , [TRef $ TMut $ TArray $ TVar 3, TInt] ~> TRef $ TMut $ TVar 3
     ]]
    [ (0, TRef TBln)
    , (1, [TRef $ TArray TBln, TInt] ~> TRef TBln)
    , (2, TBln)
    ]
    []

  , unifyTest "array-app-overload-mut"
    [([TMut $ TArray TBln, TInt] ~> TVar 0) :$= TOver 1
     [ [TRef $ TArray $ TVar 2, TInt] ~> TRef $ TVar 2
     , [TRef $ TMut $ TArray $ TVar 3, TInt] ~> TRef $ TMut $ TVar 3
     ]]
    [ (0, TRef $ TMut TBln)
    , (1, [TRef $ TMut $ TArray TBln, TInt] ~> TRef $ TMut TBln)
    , (3, TBln)
    ]
    []

  , matchTest "match-array-and-app-imt"
      ByVal
      ([TArray TBln, TInt] ~> TVar 0)
      ([TRef $ TArray $ TVar 1, TInt] ~> TRef $ TVar 1)
      (Match [] (Distance 0) Complete $ M.fromList [(0, TRef $ TVar 1), (1, TBln)])

  , matchTest "match-array-and-app-mut"
      ByVal
      ([TMut $ TArray TBln, TInt] ~> TVar 0)
      ([TRef $ TMut $ TArray $ TVar 1, TInt] ~> TRef $ TMut $ TVar 1)
      (Match [] (Distance 0) Complete $ M.fromList [(0, TRef $ TMut $ TVar 1), (1, TBln)])
  ]

