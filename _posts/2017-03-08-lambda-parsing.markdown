---
layout: post
title:  "Parsing Lambda Expressions"
date:   2017-03-08 +0100
categories: bytecode
---
In [a previous post]({{ site.baseurl }}/bytecode/2017/02/25/lambda-inspection.html) I have shown how to find the implementation method of a lambda expression given the lambda instance. In this post I show how to extract the captured arguments and how to parse the implementation method using the ASM dataflow framework.

## Extracting Type Information and the Captured Arguments
The following class contains the static information extracted about a lambda class:

``` java
public class LambdaStatic {
    public Method implementationMethod;
    public Class<?>[] capturedTypes;
    public Class<?>[] argumentTypes;

    public Expression expression;
    public LambdaAccessedMemberInfo accessedMemberInfo;
}
```

Extracted by:

``` java
LambdaInformation info = lambda.getClass().getAnnotation(LambdaInformation.class);
ClassLoader cl = info.implMethodClass().getClassLoader();
LambdaStatic stat = new LambdaStatic();
Class<?>[] samArgTypes = loadClasses(cl, Type.getMethodType(info.samMethodDesc()).getArgumentTypes());
Class<?>[] implArgTypes = loadClasses(cl, Type.getMethodType(info.implMethodDesc()).getArgumentTypes());
stat.implementationMethod = info.implMethodClass().getDeclaredMethod(info.implMethodName(), implArgTypes);
stat.argumentTypes = samArgTypes;
stat.capturedTypes = Arrays.copyOfRange(implArgTypes, 0, implArgTypes.length - samArgTypes.length);
```

Finally, all extracted information about a lambda is contained in

``` java
public class Lambda {
    public Object this_;
    public Object[] captured;
    public LambdaStatic static_;
    public LambdaAccessedMemberHandle memberHandle;
}
```
You can see the `this` reference and the captured arguments. These references are simply extracted from the `"arg$"+i`-fields of the lambda instance.

## Parsing the Implementation Method

The goal is to parse rather simple expressions such as property accesses for bidirectinal data binding or method invocations of button handlers. Therefore control stuctures such as `if`s and loops or `try-catch` blocks are not supported.

The body of the implementation methods are represented as expression. There are around 20 expression types. Some examples are:

* `ThisExpression`: the this variable
* `ArgumentExpression`: a method ArgumentExpression
* `MethodInvocationExpression`: invocation of a method
* `BinaryArithmeticExpression`: arithmetic operation such as `+` and `*`
...

ASM already contains a framework to perform an abstract execution of a method. Typically the goal of such a an execution is to determine the possible types of the values. In our case we are interested in the in the expressions the values are derived from.

The parsing happens via a custom `Interpreter` which operates on `ExpressionValue`s which are just wrappers around `Expression`s. Afterwards the return statements are located along with the returned expression. If only a single expression is found, this is the desired expression.

From the expression the last accessed member (method or field) can easily be determined, as well as the base expression the member access operates on. The last part of the puzzle is an expression evaluator:

``` java
private static class EvalVisitor implements ExpressionVisitor<Object> {
	...
	@Override
	public Object visit(GetFieldExpression expr) {
	    Object target = expr.target.accept(this);
	    return expr.field.get(target);
	}
	...
```

The full code example can be found on [github](https://github.com/ruediste/lambda-inspector).
