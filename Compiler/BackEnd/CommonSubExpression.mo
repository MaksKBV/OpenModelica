/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package CommonSubExpression
" file:        CommonSubExpression.mo
  package:     CommonSubExpression
  description: This package contains functions for the optimization module
               CommonSubExpression.

  RCS: $Id: CommonSubExpression.mo 23264 2014-11-07 07:01:20Z sjoelund.se $"

public import BackendDAE;
public import DAE;

protected import Array;
protected import BackendDAEUtil;
protected import BackendDump;
protected import BackendEquation;
protected import BackendVarTransform;
protected import BackendVariable;
protected import BaseHashSet;
protected import BaseHashTable;
protected import ComponentReference;
protected import Expression;
protected import ExpressionDump;
protected import ExpressionSolve;
protected import HashTableExpToExp;
protected import HashTableExpToIndex;
protected import HpcOmEqSystems;
protected import HpcOmTaskGraph;
protected import List;
protected import ResolveLoops;


protected
uniontype CommonSubExp
  record ASSIGNMENT_CSE
    list<Integer> eqIdcs;
    list<Integer> sharedVars;
    list<Integer> aliasVars;
  end ASSIGNMENT_CSE;
end CommonSubExp;

//
public function CSE "authors: Jan Hagemann and Lennart Ochel (FH Bielefeld, Germany)
  This module eliminates common sub expression in an acausal environment. Different options are available:
    - CSE_CALL: consider duplicate call expressions
    - CSE_EACHCALL: consider each call expressions
    - CSE_BINARY: consider duplicate binary expressions
  NOTE: This is currently just an experimental prototype to demonstrate interesting effects."
  input BackendDAE.BackendDAE daeIn;
  output BackendDAE.BackendDAE daeOut := daeIn;
algorithm
  if Flags.getConfigBool(Flags.CSE_CALL) or Flags.getConfigBool(Flags.CSE_EACHCALL) or Flags.getConfigBool(Flags.CSE_BINARY) then
    try
      daeOut := BackendDAEUtil.mapEqSystemAndFold(daeIn, CSE1, 1);
    else
      daeOut := daeIn;
    end try;
  end if;
end CSE;

public function CSE1
  input BackendDAE.EqSystem inSyst;
  input BackendDAE.Shared inShared;
  input Integer inStartIndex;
  output BackendDAE.EqSystem outSyst;
  output BackendDAE.Shared outShared := inShared;
  output Integer outStartIndex := inStartIndex;
algorithm
  outSyst := matchcontinue(inSyst)
    local
      BackendDAE.Variables orderedVars;
      BackendDAE.EquationArray orderedEqs;
      Option<BackendDAE.IncidenceMatrix> m;
      Option<BackendDAE.IncidenceMatrixT> mT;
      BackendDAE.Matching matching;
      BackendDAE.StateSets stateSets;
      BackendDAE.BaseClockPartitionKind partitionKind;
      list<BackendDAE.Var> varList;
      list<BackendDAE.Equation> eqList;
      HashTableExpToExp.HashTable HT;
      HashTableExpToIndex.HashTable HT2, HT3;

    case BackendDAE.EQSYSTEM(orderedVars, orderedEqs, m, mT, matching, stateSets, partitionKind) equation
      // BackendDump.dumpEquationList(eqList, "############## Equation-Liste: ###########");
      // BackendDump.dumpVarList(varList, "############## Variablen-Liste: ###########");
      // TODO: merge HT and HT2
      HT = HashTableExpToExp.emptyHashTableSized(49999);  //2053    4013    25343   536870879
      HT2 = HashTableExpToIndex.emptyHashTableSized(49999);
      HT3 = HashTableExpToIndex.emptyHashTableSized(49999);
      (HT, HT2, outStartIndex) = BackendEquation.traverseEquationArray(orderedEqs, foldEq, (HT, HT2, inStartIndex));
      // BaseHashTable.dumpHashTable(HT);
      // BaseHashTable.dumpHashTable(HT2);
      (orderedEqs, (HT, HT2, _, eqList, varList)) = BackendEquation.traverseEquationArray_WithUpdate(orderedEqs, foldEq2, (HT, HT2, HT3, {}, {}));
      orderedEqs = BackendEquation.addEquations(eqList, orderedEqs);
      orderedVars = BackendVariable.addVars(varList, orderedVars);
      if Flags.isSet(Flags.DUMP_CSE) then
        BackendDump.dumpEquationArray(orderedEqs, "########### Updated Equation List: #########");
        BackendDump.dumpVariables(orderedVars, "########### Updated Variable List: #########");
      end if;
    then BackendDAE.EQSYSTEM(orderedVars, orderedEqs, NONE(), NONE(), BackendDAE.NO_MATCHING(), stateSets, partitionKind);

    else inSyst;
  end matchcontinue;
end CSE1;

//
protected function foldEq2
  input BackendDAE.Equation inEq;
  input tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, HashTableExpToIndex.HashTable, list<BackendDAE.Equation>, list<BackendDAE.Var>> inTuple;
  output BackendDAE.Equation outEq;
  output tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, HashTableExpToIndex.HashTable, list<BackendDAE.Equation>, list<BackendDAE.Var>> outTuple;
algorithm
  (outEq, outTuple) := match(inEq)
    local
      BackendDAE.Equation eq;
      tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, HashTableExpToIndex.HashTable, list<BackendDAE.Equation>, list<BackendDAE.Var>> tpl;

    case BackendDAE.ALGORITHM() then (inEq, inTuple);
    case BackendDAE.WHEN_EQUATION() then (inEq, inTuple);  // not necessary
    //case BackendDAE.COMPLEX_EQUATION() then (inEq, inTuple);
    //case BackendDAE.ARRAY_EQUATION() then (inEq, inTuple);
    case BackendDAE.IF_EQUATION() then (inEq, inTuple);

    else
      equation
        (eq,(tpl,_)) = BackendEquation.traverseExpsOfEquation(inEq, traverseExpsEquation_2, (inTuple,BackendEquation.equationSource(inEq)));
      then (eq,tpl);
  end match;
end foldEq2;

//
protected function traverseExpsEquation_2
  input DAE.Exp inExp;
  input tuple<tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, HashTableExpToIndex.HashTable, list<BackendDAE.Equation>, list<BackendDAE.Var>>,DAE.ElementSource> inTuple;
  output DAE.Exp outExp;
  output tuple<tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, HashTableExpToIndex.HashTable, list<BackendDAE.Equation>, list<BackendDAE.Var>>,DAE.ElementSource> outTuple;
algorithm
  (outExp, outTuple) := Expression.traverseExpTopDown(inExp, traverseSubExp_2, inTuple);
end traverseExpsEquation_2;

//
protected function traverseSubExp_2
  input DAE.Exp inExp;
  input tuple<tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, HashTableExpToIndex.HashTable, list<BackendDAE.Equation>, list<BackendDAE.Var>>,DAE.ElementSource> inTuple;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, HashTableExpToIndex.HashTable, list<BackendDAE.Equation>, list<BackendDAE.Var>>,DAE.ElementSource> outTuple;
algorithm
  (outExp, cont, outTuple) := matchcontinue(inExp, inTuple)
    local
      DAE.Exp exp1, exp2, key, value;
      list<DAE.Exp> expLst;
      DAE.Operator op;
      Absyn.Path path;
      DAE.CallAttributes attr;
      HashTableExpToExp.HashTable HT;
      HashTableExpToIndex.HashTable HT2;
      HashTableExpToIndex.HashTable HT3;
      list<BackendDAE.Equation> eqLst, eqLst1;
      list<BackendDAE.Var> varLst, varLst1;
      Integer value2;
      DAE.ComponentRef cr;
      BackendDAE.Var var;
      BackendDAE.Equation eq;
      DAE.Type tp;
      DAE.Exp expReplaced;
      list<DAE.Exp> expLst;
      DAE.ElementSource source;

    case (key as DAE.BINARY(exp1, op, exp2), ((HT, HT2, HT3, eqLst, varLst), source)) equation
      true = Flags.getConfigBool(Flags.CSE_BINARY);
      value = BaseHashTable.get(key, HT);
      value2 = BaseHashTable.get(value, HT2);
      true = intGt(value2, 1);
      if not BaseHashTable.hasKey(value, HT3) then
        HT3 = BaseHashTable.add((value, 1), HT3);
        varLst1 = createVarsForExp(value, {});
        varLst = listAppend(varLst1, varLst);
        eq = BackendEquation.generateEquation(value, key, source /* TODO: Add CSE? */, BackendDAE.EQ_ATTR_DEFAULT_BINDING);
        eqLst = eq::eqLst;
      end if;
    then (value, true, ((HT, HT2, HT3, eqLst, varLst), source));

    case (key as DAE.CALL(path, expLst, attr), ((HT, HT2, HT3, eqLst, varLst),source)) equation
      true = Flags.getConfigBool(Flags.CSE_CALL) or Flags.getConfigBool(Flags.CSE_EACHCALL);

      value = BaseHashTable.get(key, HT);
      value2 = BaseHashTable.get(value, HT2);

      if not Flags.getConfigBool(Flags.CSE_EACHCALL) then
        true = intGt(value2, 1);
      end if;

      // debug
      if Flags.isSet(Flags.DUMP_CSE_VERBOSE) then
        print("replace :\n " + ExpressionDump.printExpStr(key) + " \n");
        print("  => " + ExpressionDump.printExpStr(value) + " \n");
      end if;

      if not BaseHashTable.hasKey(value, HT3) then

        // generate all variables, since this function might fail
        // this need to run before any HashTable is updated
        varLst1 = createVarsForExp(value, {});
        varLst = listAppend(varLst1, varLst);

        // generate the proper replacement for arrays and records
        // this need to run before any HashTable is updated
        expReplaced = prepareExpForReplace(value);

        // traverse all arguments of the function
        (expLst, ((HT, HT2, HT3, eqLst1, varLst1), source)) = Expression.traverseExpList(expLst, traverseExpsEquation_2, ((HT, HT2, HT3, {}, {}), source));
        exp1 = DAE.CALL(path, expLst, attr);
        varLst = listAppend(varLst1, varLst);
        eqLst = listAppend(eqLst1, eqLst);

        // debug
        if Flags.isSet(Flags.DUMP_CSE_VERBOSE) then
          print("create equation from:\n  LHS: " + ExpressionDump.printExpStr(value) + " \n");
          print("  RHS: " + ExpressionDump.printExpStr(key) + " \n");
        end if;

        // generate equation
        eq = BackendEquation.generateEquation(expReplaced, exp1, source /* TODO: Add CSE? */, BackendDAE.EQ_ATTR_DEFAULT_BINDING);
        eqLst = eq::eqLst;

        // update HashTable by value
        HT3 = BaseHashTable.add((value, 1), HT3);

        // use replaced expression
        value = expReplaced;

        // debug
        if Flags.isSet(Flags.DUMP_CSE_VERBOSE) then
          print("Replaced CSE Expression: " + ExpressionDump.printExpStr(key) + " \n");
          print("by equation:\n" + BackendDump.equationString(eq) + "\n");
        end if;
      else
        // use replaced expression
        value = prepareExpForReplace(value);
      end if;
    then (value, false, ((HT, HT2, HT3, eqLst, varLst), source));

    else (inExp, true, inTuple);
  end matchcontinue;
end traverseSubExp_2;

//
protected function foldEq
  input BackendDAE.Equation inEq;
  input tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, Integer> inTuple;
  output BackendDAE.Equation outEq;
  output tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, Integer> outTuple;
algorithm
  (outEq, outTuple) := match(inEq)
    local
      BackendDAE.Equation eq;
      tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, Integer> tpl;

    case BackendDAE.ALGORITHM() then (inEq, inTuple);
    case BackendDAE.WHEN_EQUATION() then (inEq, inTuple);  // not necessary
    //case BackendDAE.COMPLEX_EQUATION() then (inEq, inTuple);
    //case BackendDAE.ARRAY_EQUATION() then (inEq, inTuple);
    case BackendDAE.IF_EQUATION() then (inEq, inTuple);

    else equation
      if Flags.isSet(Flags.DUMP_CSE_VERBOSE) then
        print("\n");
        BackendDump.printEquation(inEq);
      end if;
      (eq,tpl) = BackendEquation.traverseExpsOfEquation(inEq, traverseExpsEquation_1, inTuple);
    then (eq,tpl);
  end match;
end foldEq;

//
protected function traverseExpsEquation_1
  input DAE.Exp inExp;
  input tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, Integer> inTuple;
  output DAE.Exp outExp;
  output tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, Integer> outTuple;
algorithm
  (outExp, outTuple) := Expression.traverseExpTopDown(inExp, traverseSubExp_1, inTuple);
end traverseExpsEquation_1;

//
protected function traverseSubExp_1
  input DAE.Exp inExp;
  input tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, Integer> inTuple;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<HashTableExpToExp.HashTable, HashTableExpToIndex.HashTable, Integer> outTuple;
algorithm
  (outExp, cont, outTuple) := matchcontinue(inExp, inTuple)
    local
      DAE.Exp exp1, exp2, value;
      list<DAE.Exp> expLst;
      DAE.Operator op;
      Absyn.Path path;
      HashTableExpToExp.HashTable HT;
      HashTableExpToIndex.HashTable HT2;
      list<BackendDAE.Equation> eqList;
      list<BackendDAE.Var> varList;
      Integer i, value2;
      String str;
      DAE.ComponentRef cr;
      BackendDAE.Var var;
      BackendDAE.Equation eq;
      DAE.Type tp;

    case (DAE.BINARY(exp1, op, exp2), (HT, HT2, i)) equation
      true = Flags.getConfigBool(Flags.CSE_BINARY);
      if checkOp(op) then
        if BaseHashTable.hasKey(inExp, HT) then
          value = BaseHashTable.get(inExp, HT);
          value2 = BaseHashTable.get(value, HT2);
          HT2 = BaseHashTable.update((value, value2 + 1), HT2);
        else
          str = "$CSE" + intString(i);
          cr = DAE.CREF_IDENT(str, DAE.T_REAL_DEFAULT,{});
          value = DAE.CREF(cr, DAE.T_REAL_DEFAULT);
          HT = BaseHashTable.add((inExp, value), HT);
          HT2 = BaseHashTable.add((value, 1), HT2);
          if commutativeBinaryExp(op) then
            HT = BaseHashTable.add((DAE.BINARY(exp2, op, exp1), value), HT);
          end if;
          i = i+1;
        end if;
      end if;
    then (inExp, true, (HT, HT2, i));

    case (DAE.IFEXP(_), _)
    then (inExp, false, inTuple);

    case (DAE.CALL(path=Absyn.IDENT("der")), _)
    then (inExp, false, inTuple);
    case (DAE.CALL(path=Absyn.IDENT("smooth")), _)
    then (inExp, false, inTuple);
    case (DAE.CALL(path=Absyn.IDENT("noEvent")), _)
    then (inExp, false, inTuple);
    case (DAE.CALL(path=Absyn.IDENT("semiLinear")), _)
    then (inExp, false, inTuple);


    case (DAE.CALL(path=path, attr=DAE.CALL_ATTR(ty=tp)), (HT, HT2, i)) equation
      true = Flags.getConfigBool(Flags.CSE_CALL) or Flags.getConfigBool(Flags.CSE_EACHCALL);
      if BaseHashTable.hasKey(inExp, HT) then
        value = BaseHashTable.get(inExp, HT);
        value2 = BaseHashTable.get(value, HT2) + 1;
        HT2 = BaseHashTable.update((value, value2), HT2);
        if Flags.isSet(Flags.DUMP_CSE_VERBOSE) then
          print("Found CSE Expression (count: " + intString(value2) + "): " + ExpressionDump.printExpStr(inExp) + " \n");
        end if;
      else
        (value, i) = createReturnExp(tp, i);
        HT = BaseHashTable.add((inExp, value), HT);
        HT2 = BaseHashTable.add((value, 1), HT2);
        i = i+1;
        if Flags.isSet(Flags.DUMP_CSE_VERBOSE) then
          print("Found CSE Expression first time: " + ExpressionDump.printExpStr(inExp) + " \n");
        end if;
      end if;
    then (inExp, true, (HT, HT2, i));

    else (inExp, true, inTuple);
  end matchcontinue;
end traverseSubExp_1;

//
protected function commutativeBinaryExp
  input DAE.Operator inOp;
  output Boolean outB;
algorithm
  outB := match(inOp)
    case DAE.MUL() then true;
    case DAE.ADD() then true;
    else false;
  end match;
end commutativeBinaryExp;

//
protected function checkOp
  input DAE.Operator inOp;
  output Boolean outB;
algorithm
  outB:=match(inOp)
    case DAE.ADD() then true;
    case DAE.SUB() then true;
    case DAE.MUL() then true;
    case DAE.DIV() then true;
    case DAE.POW() then true;
    case DAE.UMINUS() then true;
    else false;
  end match;
end checkOp;

protected function createReturnExp
  input DAE.Type inType;
  input Integer inUniqueCSEIndex;
  output DAE.Exp outExp;
  output Integer outUniqueCSEIndex;
algorithm
  (outExp, outUniqueCSEIndex) := match (inType)
    local
      Integer i;
      String str;
      DAE.Exp value;
      DAE.ComponentRef cr;
      list<DAE.Type> typeLst;
      list<DAE.Exp> expLst;
      DAE.Dimensions dims;
      DAE.Type tp;
      list<DAE.ComponentRef> crefs;
      Absyn.Path path;
      list<DAE.Var> varLst;
      list<String> varNames;
      DAE.TypeSource tpSource;

    case DAE.T_REAL() equation
      str = "$CSE" + intString(inUniqueCSEIndex);
      cr = DAE.CREF_IDENT(str, DAE.T_REAL_DEFAULT,{});
      value = DAE.CREF(cr, DAE.T_REAL_DEFAULT);
    then (value, inUniqueCSEIndex+1);

    case DAE.T_INTEGER() equation
      str = "$CSE" + intString(inUniqueCSEIndex);
      cr = DAE.CREF_IDENT(str, DAE.T_INTEGER_DEFAULT,{});
      value = DAE.CREF(cr, DAE.T_INTEGER_DEFAULT);
    then (value, inUniqueCSEIndex+1);

    case DAE.T_STRING() equation
      str = "$CSE" + intString(inUniqueCSEIndex);
      cr = DAE.CREF_IDENT(str, DAE.T_STRING_DEFAULT,{});
      value = DAE.CREF(cr, DAE.T_STRING_DEFAULT);
    then (value, inUniqueCSEIndex+1);

    case DAE.T_BOOL() equation
      str = "$CSE" + intString(inUniqueCSEIndex);
      cr = DAE.CREF_IDENT(str, DAE.T_BOOL_DEFAULT,{});
      value = DAE.CREF(cr, DAE.T_BOOL_DEFAULT);
    then (value, inUniqueCSEIndex+1);

    case DAE.T_CLOCK() equation
      str = "$CSE" + intString(inUniqueCSEIndex);
      cr = DAE.CREF_IDENT(str, DAE.T_CLOCK_DEFAULT,{});
      value = DAE.CREF(cr, DAE.T_CLOCK_DEFAULT);
    then (value, inUniqueCSEIndex+1);

    case DAE.T_TUPLE(types=typeLst) equation
      (expLst, i) = List.mapFold(typeLst, createReturnExp, inUniqueCSEIndex);
      value = DAE.TUPLE(expLst);
    then (value, i+1);

    case DAE.T_ARRAY(ty=tp, dims=dims) equation
      (value, i) = createReturnExp(tp, inUniqueCSEIndex);
      cr = Expression.expCref(value);
      crefs = ComponentReference.expandArrayCref(cr, dims);
      expLst = List.map(crefs, Expression.crefExp);
      value = DAE.ARRAY(inType, true, expLst);
    then (value, i+1);

    // record types
    case DAE.T_COMPLEX(varLst=varLst,complexClassType=ClassInf.RECORD(path),source=tpSource) equation
      str = "$CSE" + intString(inUniqueCSEIndex);
      cr = DAE.CREF_IDENT(str, inType, {});
      crefs = ComponentReference.expandCref(cr, true);
      expLst = List.map(crefs, Expression.crefExp);
      varNames = List.map(varLst, Expression.varName);
      value = DAE.RECORD(path, expLst, varNames, inType);
    then (value, inUniqueCSEIndex+1);

    // all other are failing cases
    else fail();
  end match;
end createReturnExp;

protected function createVarsForExp
  input DAE.Exp inExp;
  input list<BackendDAE.Var> inAccumVarLst;
  output list<BackendDAE.Var> outVarLst;
algorithm
  (outVarLst) := match (inExp)
    local
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> crefs;
      list<DAE.Exp> expLst;
      BackendDAE.Var var;

    case DAE.CREF(componentRef=cr) guard(not Expression.isArrayType(Expression.typeof(inExp))
                                          and not Expression.isRecordType(Expression.typeof(inExp)))
    equation
      var = BackendVariable.createCSEVar(cr);
    then var::inAccumVarLst;

    /* consider also array and record crefs */
    /* TODO: Acivate that case, now it produces wrong types
             in the created variables, it seems that expandCref
             has an issue.
    */
    /*
    case DAE.CREF(componentRef=cr) equation
      crefs = ComponentReference.expandCref(cr, true);
      false = valueEq({cr},crefs); // Not an expanded element
      expLst = List.map(crefs, Expression.crefExp);
      outVarLst = List.fold(expLst, createVarsForExp, inAccumVarLst);
    then outVarLst;
    */

    case DAE.TUPLE(expLst) equation
      outVarLst = List.fold(expLst, createVarsForExp, inAccumVarLst);
    then outVarLst;

    case DAE.ARRAY(array=expLst) equation
      outVarLst = List.fold(expLst, createVarsForExp, inAccumVarLst);
    then outVarLst;

    case DAE.RECORD(exps=expLst) equation
      outVarLst = List.fold(expLst, createVarsForExp, inAccumVarLst);
    then outVarLst;

    // all other are failing cases
    else fail();
  end match;
end createVarsForExp;

protected function prepareExpForReplace
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  (outExp) := match (inExp)
    local
      DAE.ComponentRef cr;
      DAE.Exp e;
      list<DAE.Exp> expLst;
      DAE.Type ty;
      Boolean scalar;

    case DAE.TUPLE(PR=expLst) equation
      expLst = List.map(expLst, prepareExpForReplace);
    then DAE.TUPLE(expLst);

    case DAE.ARRAY(array=e::_, ty=ty, scalar=scalar) equation
      cr = Expression.expCref(e);
      cr = ComponentReference.crefStripLastSubs(cr);
      cr = ComponentReference.crefSetType(cr, ty);
      e = Expression.crefExp(cr);
    then e;

    case DAE.RECORD(exps=e::_) equation
      cr = Expression.expCref(e);
      cr = ComponentReference.crefStripLastIdent(cr);
      e = Expression.crefExp(cr);
    then e;

    else inExp;
  end match;
end prepareExpForReplace;

// =============================================================================
// Common Sub Expressions
//
// =============================================================================

public function commonSubExpressionReplacement"detects common sub expressions and introduces alias variables for them.
REMARK: this is just a basic prototype. feel free to extend.
author:Waurich TUD 2014-11"
  input BackendDAE.BackendDAE daeIn;
  output BackendDAE.BackendDAE daeOut;
protected
  BackendDAE.EqSystems eqs;
  BackendDAE.Shared shared;
algorithm
    //print("SYSTEM IN\n");
    //BackendDump.printBackendDAE(daeIn);
    if Flags.isSet(Flags.DISABLE_COMSUBEXP) then
      daeOut := daeIn;
    else
      daeOut := BackendDAEUtil.mapEqSystem(daeIn,commonSubExpression);
    end if;
    //print("SYSTEM OUT\n");
    //BackendDump.printBackendDAE(daeOut);
end commonSubExpressionReplacement;

protected function commonSubExpression
  input BackendDAE.EqSystem sysIn;
  input BackendDAE.Shared sharedIn;
  output BackendDAE.EqSystem sysOut;
  output BackendDAE.Shared sharedOut;
algorithm
  (sysOut,sharedOut) := matchcontinue(sysIn,sharedIn)
    local
    DAE.FunctionTree functionTree;
    BackendDAE.Variables vars;
    BackendDAE.EquationArray eqs;
    BackendDAE.Shared shared;
    BackendDAE.EqSystem syst;
    BackendDAE.IncidenceMatrix m,mT;
    list<Integer> eqIdcs;
    list<CommonSubExp> cseLst;
  case(BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqs), BackendDAE.SHARED(functionTree=functionTree))
    equation
      (_,m,mT) = BackendDAEUtil.getIncidenceMatrix(sysIn,BackendDAE.ABSOLUTE(),SOME(functionTree));
          //print("start this eqSystem\n");
          //BackendDump.dumpEqSystem(sysIn,"eqSystem input");
          //BackendDump.dumpIncidenceMatrix(m);
          //BackendDump.dumpIncidenceMatrixT(mT);
      cseLst = commonSubExpressionFind(m,mT,vars,eqs);
      //if List.isNotEmpty(cseLst) then print("update "+stringDelimitList(List.map(cseLst,printCSE),"")+"\n");end if;
      (syst,shared) = commonSubExpressionUpdate(cseLst,m,mT,sysIn,sharedIn,{},{});
          //print("done this eqSystem\n");
          //BackendDump.dumpEqSystem(syst,"eqSystem");
          //BackendDump.printShared(shared);
      then (syst,shared);
    else (sysIn,sharedIn);
  end matchcontinue;
end commonSubExpression;

protected function commonSubExpressionFind
  input BackendDAE.IncidenceMatrix mIn;
  input BackendDAE.IncidenceMatrix mTIn;
  input BackendDAE.Variables varsIn;
  input BackendDAE.EquationArray eqsIn;
  output list<CommonSubExp> cseOut;
protected
  list<Integer> eqIdcs,varIdcs,lengthLst,range;
  list<list<Integer>> arrLst;
  list<list<Integer>> partitions;
  BackendDAE.Variables vars;
  BackendDAE.EquationArray eqs;
  BackendDAE.EqSystem eqSys;
  BackendDAE.IncidenceMatrix m,mT;
  list<CommonSubExp> cseLst2,cseLst3;
  list<tuple<Boolean,String>> varAtts,eqAtts;
algorithm
  try
    range := List.intRange(arrayLength(mIn));
    arrLst := arrayList(mIn);
    lengthLst := List.map(arrLst,listLength);

    // check for CSE of length 1
    //print("CHECK FOR CSE 2\n");
    (_,eqIdcs) := List.filter1OnTrueSync(lengthLst,intEq,2,range);
    varIdcs := List.unique(List.flatten(List.map1(eqIdcs,Array.getIndexFirst,mIn)));
    vars := BackendVariable.listVar1(List.map1(varIdcs,BackendVariable.getVarAtIndexFirst,varsIn));
    eqs := BackendEquation.listEquation(BackendEquation.getEqns(eqIdcs,eqsIn));
    eqSys := BackendDAE.EQSYSTEM(vars,eqs,NONE(),NONE(),BackendDAE.NO_MATCHING(),{},BackendDAE.UNKNOWN_PARTITION());
    (_,m,mT) := BackendDAEUtil.getIncidenceMatrix(eqSys,BackendDAE.ABSOLUTE(),NONE());
        //BackendDump.dumpEqSystem(eqSys,"reduced system for CSE 2");
        //BackendDump.dumpIncidenceMatrix(m);
        //BackendDump.dumpIncidenceMatrix(mT);
        //varAtts := List.threadMap(List.fill(false,listLength(varIdcs)),List.fill("",listLength(varIdcs)),Util.makeTuple);
        //eqAtts := List.threadMap(List.fill(false,listLength(eqIdcs)),List.fill("",listLength(eqIdcs)),Util.makeTuple);
        //HpcOmEqSystems.dumpEquationSystemBipartiteGraph2(vars,eqs,m,varAtts,eqAtts,"CSE2");
    partitions := arrayList(ResolveLoops.partitionBipartiteGraph(m,mT));
        //print("the partitions for system  : \n"+stringDelimitList(List.map(partitions,HpcOmTaskGraph.intLstString),"\n")+"\n");
    cseLst2 := List.fold(partitions,function getCSE2(m=m,mT=mT,vars=vars,eqs=eqs,eqMap=eqIdcs,varMap=varIdcs),{});

    // check for CSE of length 2
    //print("CHECK FOR CSE 3\n");
    (_,eqIdcs) := List.filter1OnTrueSync(lengthLst,intEq,3,range);
    varIdcs := List.unique(List.flatten(List.map1(eqIdcs,Array.getIndexFirst,mIn)));
    vars := BackendVariable.listVar1(List.map1(varIdcs,BackendVariable.getVarAtIndexFirst,varsIn));
    eqs := BackendEquation.listEquation(BackendEquation.getEqns(eqIdcs,eqsIn));
    eqSys := BackendDAE.EQSYSTEM(vars,eqs,NONE(),NONE(),BackendDAE.NO_MATCHING(),{},BackendDAE.UNKNOWN_PARTITION());
    (_,m,mT) := BackendDAEUtil.getIncidenceMatrix(eqSys,BackendDAE.ABSOLUTE(),NONE());
        //BackendDump.dumpEqSystem(eqSys,"reduced system for CSE 3");
        //BackendDump.dumpIncidenceMatrix(m);
        //BackendDump.dumpIncidenceMatrix(mT);
        //varAtts := List.threadMap(List.fill(false,listLength(varIdcs)),List.fill("",listLength(varIdcs)),Util.makeTuple);
        //eqAtts := List.threadMap(List.fill(false,listLength(eqIdcs)),List.fill("",listLength(eqIdcs)),Util.makeTuple);
        //HpcOmEqSystems.dumpEquationSystemBipartiteGraph2(vars,eqs,m,varAtts,eqAtts,"CSE3");
    partitions := arrayList(ResolveLoops.partitionBipartiteGraph(m,mT));
        //print("the partitions for system  : \n"+stringDelimitList(List.map(partitions,HpcOmTaskGraph.intLstString),"\n")+"\n");
    cseLst3 := List.fold(partitions,function getCSE3(m=m,mT=mT,vars=vars,eqs=eqs,eqMap=eqIdcs,varMap=varIdcs),{});
    cseOut := listAppend(cseLst2,cseLst3);
    //print("the cses : \n"+stringDelimitList(List.map(cseOut,printCSE),"\n")+"\n");
  else
    cseOut := {};
  end try;
end commonSubExpressionFind;

protected function getCSE2"traverses the partitions and checks for CSE2 i.e a=b+const. ; c = b+const. --> a=c
author:Waurich TUD 2014-11"
  input list<Integer> partition;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrix mT;
  input BackendDAE.Variables vars;  // for partition
  input BackendDAE.EquationArray eqs;  // for partition
  input list<Integer> eqMap;
  input list<Integer> varMap;
  input list<CommonSubExp> cseIn;
  output list<CommonSubExp> cseOut;
algorithm
  cseOut := matchcontinue(partition,m,mT,vars,eqs,eqMap,varMap,cseIn)
  local
    Integer sharedVarIdx,eqIdx1,eqIdx2,varIdx1,varIdx2;
    list<Integer> varIdcs1,varIdcs2,sharedVarIdcs,eqIdcs;
    BackendDAE.Equation eq1,eq2;
    BackendDAE.Var sharedVar,var1,var2;
    DAE.Exp varExp1,varExp2,lhs,rhs1,rhs2;
  case({eqIdx1,eqIdx2},_,_,_,_,_,_,_)
    equation
        //print("partition "+stringDelimitList(List.map(partition,intString),", ")+"\n");
      // the partition consists of 2 equations
      varIdcs1 = arrayGet(m,eqIdx1);
      varIdcs2 = arrayGet(m,eqIdx2);
      (sharedVarIdcs,varIdcs1,varIdcs2) = List.intersection1OnTrue(varIdcs1,varIdcs2,intEq);
        //print("sharedVarIdcs "+stringDelimitList(List.map(sharedVarIdcs,intString),", ")+"\n");
      {varIdx1} = varIdcs1;
      {varIdx2} = varIdcs2;
      {sharedVarIdx} = sharedVarIdcs;
      {eq1,eq2} = BackendEquation.getEqns(partition,eqs);
      sharedVar = BackendVariable.getVarAt(vars,sharedVarIdx);
      var1 = BackendVariable.getVarAt(vars,varIdx1);
      var2 = BackendVariable.getVarAt(vars,varIdx2);

      // compare the actual equations
      varExp1 = BackendVariable.varExp(var1);
      varExp2 = BackendVariable.varExp(var2);
      BackendDAE.EQUATION(exp=lhs,scalar=rhs1) = eq1;
      (rhs1,_) = ExpressionSolve.solve(lhs,rhs1,varExp1);
      BackendDAE.EQUATION(exp=lhs,scalar=rhs2) = eq2;
      (rhs2,_) = ExpressionSolve.solve(lhs,rhs2,varExp2);
      true = Expression.expEqual(rhs1,rhs2);
         //print("rhs1 " +ExpressionDump.printExpStr(rhs1)+"\n");
         //print("rhs2 " +ExpressionDump.printExpStr(rhs2)+"\n");
         //print("is equal\n");
      // build CSE
      sharedVarIdcs = List.map1(sharedVarIdcs,List.getIndexFirst,varMap);
      varIdcs1 = listAppend(varIdcs1,varIdcs2);
      varIdcs1 = List.map1(varIdcs1,List.getIndexFirst,varMap);
      eqIdcs = List.map1(partition,List.getIndexFirst,eqMap);
    then ASSIGNMENT_CSE(eqIdcs,sharedVarIdcs,varIdcs1)::cseIn;
  else cseIn;
  end matchcontinue;
end getCSE2;

protected function getCSE3"traverses the partitions and checks for CSE3 i.e a=b+c+const. ; d = b+c+const. --> a=d
author:Waurich TUD 2014-11"
  input list<Integer> partition;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrix mT;
  input BackendDAE.Variables vars;  // for partition
  input BackendDAE.EquationArray eqs;  // for partition
  input list<Integer> eqMap;
  input list<Integer> varMap;
  input list<CommonSubExp> cseIn;
  output list<CommonSubExp> cseOut;
algorithm
  cseOut := matchcontinue(partition,m,mT,vars,eqs,eqMap,varMap,cseIn)
  local
    Integer sharedVarIdx,eqIdx1,eqIdx2,varIdx1,varIdx2;
    list<Integer> varIdcs1,varIdcs2,sharedVarIdcs,eqIdcs;
    list<Integer> loop1;
    BackendDAE.Equation eq1,eq2;
    BackendDAE.Var var1,var2;
    DAE.Exp varExp1,varExp2,lhs,rhs1,rhs2;
  case(_,_,_,_,_,_,_,_)
    equation
          //print("partition "+stringDelimitList(List.map(partition,intString),", ")+"\n");
      // partition has only one loop
      ({loop1},_,_) = ResolveLoops.resolveLoops_findLoops({partition},m,mT,{},{},{});
          //print("loop1 "+stringDelimitList(List.map(loop1,intString),", ")+"\n");
      {eqIdx1,eqIdx2} = loop1;
      varIdcs1 = arrayGet(m,eqIdx1);
      varIdcs2 = arrayGet(m,eqIdx2);
      (sharedVarIdcs,varIdcs1,varIdcs2) = List.intersection1OnTrue(varIdcs1,varIdcs2,intEq);
        //print("sharedVarIdcs "+stringDelimitList(List.map(sharedVarIdcs,intString),", ")+"\n");
        //print("varIdcs1 "+stringDelimitList(List.map(varIdcs1,intString),", ")+"\n");
        //print("varIdcs2 "+stringDelimitList(List.map(varIdcs2,intString),", ")+"\n");
      {varIdx1} = varIdcs1;
      {varIdx2} = varIdcs2;
      {eq1,eq2} = BackendEquation.getEqns(loop1,eqs);
      var1 = BackendVariable.getVarAt(vars,varIdx1);
      var2 = BackendVariable.getVarAt(vars,varIdx2);

      // compare the actual equations
      varExp1 = BackendVariable.varExp(var1);
      varExp2 = BackendVariable.varExp(var2);
      BackendDAE.EQUATION(exp=lhs,scalar=rhs1) = eq1;
      (rhs1,_) = ExpressionSolve.solve(lhs,rhs1,varExp1);
      BackendDAE.EQUATION(exp=lhs,scalar=rhs2) = eq2;
      (rhs2,_) = ExpressionSolve.solve(lhs,rhs2,varExp2);
      true = Expression.expEqual(rhs1,rhs2);
         //print("rhs1 " +ExpressionDump.printExpStr(rhs1)+"\n");
         //print("rhs2 " +ExpressionDump.printExpStr(rhs2)+"\n");
         //print("is equal\n");
      // build CSE
      sharedVarIdcs = List.map1(sharedVarIdcs,List.getIndexFirst,varMap);
      varIdcs1 = listAppend(varIdcs1,varIdcs2);
      varIdcs1 = List.map1(varIdcs1,List.getIndexFirst,varMap);
      eqIdcs = List.map1(loop1,List.getIndexFirst,eqMap);
    then ASSIGNMENT_CSE(eqIdcs,sharedVarIdcs,varIdcs1)::cseIn;
  else cseIn;
  end matchcontinue;
end getCSE3;


protected function commonSubExpressionUpdate"updates the eqSystem and shared according to the cse.
author:Waurich TUD 2014-11"
  input list<CommonSubExp> tplsIn;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrix mT;
  input BackendDAE.EqSystem sysIn;
  input BackendDAE.Shared sharedIn;
  input list<Integer> deleteEqLstIn;
  input list<DAE.ComponentRef> deleteCrefsIn;
  output BackendDAE.EqSystem sysOut;
  output BackendDAE.Shared sharedOut;
algorithm
  (sysOut,sharedOut) := matchcontinue(tplsIn,m,mT,sysIn,sharedIn,deleteEqLstIn,deleteCrefsIn)
    local
      Integer sharedVar,eqIdx1,eqIdx2,varIdx1,varIdx2,varIdxRepl,varIdxAlias,eqIdxDel,eqIdxLeft;
      list<Integer> eqIdcs,eqs1,eqs2,vars1,vars2,aliasVars;
      list<CommonSubExp> rest;
      BackendDAE.Var var1,var2;
      BackendVarTransform.VariableReplacements repl;
      BackendDAE.StateSets stateSets;
      BackendDAE.BaseClockPartitionKind partitionKind;
      BackendDAE.Variables vars;
      BackendDAE.EquationArray eqs;
      BackendDAE.EqSystem eqSys;
      BackendDAE.Shared shared;
      DAE.Exp varExp;
      DAE.ComponentRef cref;
      list<BackendDAE.Equation> eqLst;
  case({},_,_,BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqs,stateSets=stateSets,partitionKind=partitionKind),_,_,_)
    equation
      // remove superfluous equations
    eqLst = BackendEquation.equationList(eqs);
    eqLst = List.deletePositions(eqLst,List.map1(deleteEqLstIn,intSub,1));
    eqs = BackendEquation.listEquation(eqLst);

    // remove alias from vars
    vars = BackendVariable.deleteCrefs(deleteCrefsIn,vars);
    eqSys = BackendDAE.EQSYSTEM(vars,eqs,NONE(),NONE(),BackendDAE.NO_MATCHING(),stateSets,partitionKind);
    then (eqSys,sharedIn);
  case(ASSIGNMENT_CSE(eqIdcs={eqIdx1,eqIdx2},aliasVars={varIdx1,varIdx2})::rest,_,_,BackendDAE.EQSYSTEM(orderedVars=vars,orderedEqs=eqs,stateSets=stateSets,partitionKind=partitionKind),_,_,_)
    equation
     // update the equations
     repl = BackendVarTransform.emptyReplacements();
     eqs1 = arrayGet(mT,varIdx1);
     eqs2 = arrayGet(mT,varIdx2);
           //print("eqs1 "+stringDelimitList(List.map(eqs1,intString),", ")+"\n");
           //print("eqs2 "+stringDelimitList(List.map(eqs2,intString),", ")+"\n");
     //true = intEq(listLength(eqs1),1) or intEq(listLength(eqs2),1);  // choose the variable to be removed, that does not influence the causalization
     if intLe(listLength(eqs2),listLength(eqs1)) then varIdxAlias = varIdx2; varIdxRepl = varIdx1; else varIdxAlias = varIdx1; varIdxRepl = varIdx2; end if;
     if intLe(listLength(eqs2),listLength(eqs1)) then eqIdxDel = eqIdx2; eqIdxLeft = eqIdx1; else eqIdxDel = eqIdx1; eqIdxLeft = eqIdx2; end if;

     var1 = BackendVariable.getVarAt(vars,varIdxAlias);
     var2 = BackendVariable.getVarAt(vars,varIdxRepl);
     false = BackendVariable.isStateVar(var1) or BackendDAEUtil.isVarDiscrete(var1);

     cref = BackendVariable.varCref(var2);
     varExp = BackendVariable.varExp(var1);
     repl = BackendVarTransform.addReplacement(repl,cref,varExp,NONE());
         //BackendVarTransform.dumpReplacements(repl);
     eqIdcs = arrayGet(mT,varIdxRepl);
     eqLst = BackendEquation.getEqns(eqIdcs,eqs);
     (eqLst,_) = BackendVarTransform.replaceEquations(eqLst,repl,NONE());
     eqs = List.threadFold(eqIdcs,eqLst,BackendEquation.setAtIndexFirst,eqs);

     // transfer initial value
     if BackendVariable.varHasStartValue(var2) and not BackendVariable.varHasStartValue(var1) then var1 = BackendVariable.setVarStartValue(var1,BackendVariable.varStartValue(var2));
        var1 = BackendVariable.setVarFixed(var1,BackendVariable.varFixed(var2)) ; end if;
     vars = BackendVariable.setVarAt(vars,varIdxAlias,var1);

     // add alias to shared
     var2 = BackendVariable.setBindExp(var2,SOME(varExp));
     shared = updateAllAliasVars(sharedIn,repl);
     shared = BackendVariable.addAliasVarDAE(var2,shared);
     eqSys = BackendDAE.EQSYSTEM(vars,eqs,NONE(),NONE(),BackendDAE.NO_MATCHING(),stateSets,partitionKind);
    then commonSubExpressionUpdate(rest,m,mT,eqSys,shared,eqIdxDel::deleteEqLstIn,cref::deleteCrefsIn);
 case(_::rest,_,_,_,_,_,_)
  then commonSubExpressionUpdate(rest,m,mT,sysIn,sharedIn,deleteEqLstIn,deleteCrefsIn);
  end matchcontinue;
end commonSubExpressionUpdate;


protected function updateAllAliasVars"replaces all bindingExps in the aliasVars.
author:Waurich TUD 2014-11"
  input BackendDAE.Shared sharedIn;
  input BackendVarTransform.VariableReplacements repl;
  output BackendDAE.Shared sharedOut;
protected
  BackendDAE.Variables aliasVars;
algorithm
  BackendDAE.SHARED(aliasVars=aliasVars) := sharedIn;
  (aliasVars,_) := BackendVariable.traverseBackendDAEVarsWithUpdate(aliasVars,replaceBindings,repl);
  sharedOut := BackendDAEUtil.replaceAliasVarsInShared(sharedIn,aliasVars);
end updateAllAliasVars;

protected function replaceBindings"traversal function to replace bidning exps.
author:Waurich TUD 2014-11"
  input BackendDAE.Var inVar;
  input BackendVarTransform.VariableReplacements replIn;
  output BackendDAE.Var outVar;
  output BackendVarTransform.VariableReplacements replOut;
algorithm
  outVar := BackendVarTransform.replaceBindingExp(inVar,replIn);
  replOut := replIn;
end replaceBindings;

protected function printCSE"prints a CSE tuple string.
author:Waurich TUD 2014-11"
  input CommonSubExp cse;
  output String s;
algorithm
  s := matchcontinue(cse)
local
  list<Integer> eqIdcs;
  list<Integer> sharedVars;
  list<Integer> aliasVars;
    case(ASSIGNMENT_CSE(eqIdcs=eqIdcs,sharedVars=sharedVars,aliasVars=aliasVars))
  then "ASSIGN_CSE: eqs{"+stringDelimitList(List.map(eqIdcs,intString),", ")+"}"+"   sharedVars{"+stringDelimitList(List.map(sharedVars,intString),", ")+"}"+"   aliasVars{"+stringDelimitList(List.map(aliasVars,intString),", ")+"}";
    end matchcontinue;
end printCSE;
annotation(__OpenModelica_Interface="backend");

end CommonSubExpression;
