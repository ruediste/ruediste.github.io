---
layout: post
title:  "Java Lambda Inspection by Patching the LambdaMetafactory"
date:   2017-02-25 06:33:54 +0100
categories: bytecode
---
Java lamdas provide nice syntax to declare a piece of code which can be passed around. Unfortunately it is difficult to inspect the code itself to answer questions like "Which property is accessed?" (for bidirectional binding or database queries) or "Which method has been invoked?" (to provide a label for the method). I'll show you how to patch the LambdaMetafactory to make such inspection possible.

A lambda expression is compiled to a synthetic implementation method within the class defining the lambda. At runtime, the `LambdaMetafactory` is invoked using `INVOKEDYNAMIC` which, in it's current implementation, dynamically generates an anonymous proxy class that implements the required interface and delegates to the implementation method.

There are a couple of methods to get a hold of the implementation method given the lambda instance:

* If the lambda is serializable the serialized form of the lambda contains the class and name of the implementation method. This can be exploited by first serializing the lambda and then inspecting the result. The down side is that the captured arguments have to be serializable, which might cause issues.

* By specifying `jdk.internal.lambda.dumpProxyClasses` the bytecode of the proxy class is dumped to a directory. Since the proxy class names are unique, the bytecode can be accessed by the class name, the implementation of the abstract method of the interface parsed which leads to the implementation method. The required dumping and parsing of the class files is not my taste.

* Using bytecode manipulation it is possible to replace the call to to the `LambdaMetafactory` with a call to a custom factory which uses a delegating proxy to provide the required information. But this has some runtime overhead.

But there is an elegant option with little disadvantages: What if the `LambdaMetafactory` would put an annotation on the generated classes providing the required information?

``` java
/**
 * Annotation added to lambda classes to provide information about
 * the implementation method of the lambda.
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
public @interface LambdaInformation {

    /**
     * Class defining the implementation method
     */
    Class<?>implMethodClass();

    /**
     * Name of the implementation method
     */
    String implMethodName();

    /**
     * Descriptor of the implementation method
     */
    String implMethodDesc();

    /**
     * Class declaring the single abstract method implemented by the lambda
     */
    Class<?>samClass();

    /**
     * Name of the single abstract method in the interface of the lambda
     */
    String samMethodName();

    /**
     * Descriptor of the single abstact method in the interface of the lambda
     */
    String samMethodDesc();
}
```

This can be done using the following tools:

* The [EA Agent Loader](https://github.com/electronicarts/ea-agent-loader) to load a java agent dynamically at runtime
* A [java agent](https://docs.oracle.com/javase/7/docs/api/java/lang/instrument/package-summary.html) to register a `ClassFileTransformer`
* A `ClassFileTransformer` to change the bytecode of the `InnerClassLambdaMetafactory` which is used by the `LambdaMetafactory`

So, let's start with the agent:

``` java
public class LambdaInspectorAgent {
    public static void agentmain(String agentArgs, Instrumentation inst) {
        premain(agentArgs, inst);
    }

    public static void premain(String agentArgs, Instrumentation inst) {
        inst.addTransformer(new InnerClassLambdaMetafactoryTransformer(), true);
        try {
            inst.retransformClasses(Class.forName("java.lang.invoke.InnerClassLambdaMetafactory"));
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
		...
```

We see how the transformer is registered and the `InnerClassLambdaMetafactory` is retransformed. This gives our transformer a chance to change the metafactory. The agent is loaded simply by calling

``` java
public static void setup() {
  AgentLoader.loadAgentClass(LambdaInspectorAgent.class.getName(), "");
}
```
Remains the implementation of the `ClassFileTransformer`:

``` java
private static final class InnerClassLambdaMetafactoryTransformer implements ClassFileTransformer {
  @Override
  public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
          ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
      if (className.equals("java/lang/invoke/InnerClassLambdaMetafactory")) {
				...
```

This part makes sure only the `InnerClassLambdaMetafactory` is beeing transformed. Then we fire up a `ClassVisitor` with a special `MethodVisitor`

``` java
ClassReader cr = new ClassReader(classfileBuffer);
  ClassWriter cw = new ClassWriter(cr, 0);
  cr.accept(new ClassVisitor(Opcodes.ASM5, cw) {
      @Override
      public MethodVisitor visitMethod(int access, String name, String desc, String signature,
              String[] exceptions) {
          return new MethodVisitor(Opcodes.ASM5,
                  super.visitMethod(access, name, desc, signature, exceptions)) {
              @Override
              public void visitMethodInsn(int opcode, String owner, String name, String desc,
                      boolean itf) {
                  super.visitMethodInsn(opcode, owner, name, desc, itf);
									if ("jdk/internal/org/objectweb/asm/ClassWriter".equals(owner)
																			 && "visit".equals(name)) {
									  ...
```
The `MethodVisitor` does nothing except in the case it visits the invocation of `ClassWriter.visit()`. This is the spot the metafactory starts emitting the proxy class and we can patch it to add the desired `LambdaInformation` annotation:

``` java
// get ClassWriter
mv.visitVarInsn(Opcodes.ALOAD, 0);
mv.visitFieldInsn(Opcodes.GETFIELD, "java/lang/invoke/InnerClassLambdaMetafactory",
		"cw", "Ljdk/internal/org/objectweb/asm/ClassWriter;");

// visitAnnotation()
mv.visitLdcInsn("Lcom/github/ruediste/lambdaInspector/LambdaInformation;");
mv.visitInsn(Opcodes.ICONST_1);
mv.visitMethodInsn(Opcodes.INVOKEVIRTUAL,
		"jdk/internal/org/objectweb/asm/ClassWriter", "visitAnnotation",
		"(Ljava/lang/String;Z)Ljdk/internal/org/objectweb/asm/AnnotationVisitor;",
		false);

// impl method name
mv.visitInsn(Opcodes.DUP);
mv.visitLdcInsn("implMethodName");
mv.visitVarInsn(Opcodes.ALOAD, 0);
mv.visitFieldInsn(Opcodes.GETFIELD, "java/lang/invoke/InnerClassLambdaMetafactory",
		"implMethodName", "Ljava/lang/String;");
mv.visitMethodInsn(Opcodes.INVOKEVIRTUAL,
		"jdk/internal/org/objectweb/asm/AnnotationVisitor", "visit",
		"(Ljava/lang/String;Ljava/lang/Object;)V", false);
...
```
We first get a hold on the class writer, then start an annotation and then extract each piece of information we are interested in from the instance variables of the metafactory and place in in the annotation.

Remains a test to confirm it all works:

``` java
@Test
public void testInspector() throws Exception {
	LambdaInspector.setup();
	Runnable run = () -> {
	};
	LambdaInformation info = run.getClass().getAnnotation(LambdaInformation.class);
	assertEquals(LambdaInspectorTest.class, info.implMethodClass());
	assertEquals("lambda$0", info.implMethodName());
	assertEquals("()V", info.implMethodDesc());
	assertEquals(Runnable.class, info.samClass());
	assertEquals("run", info.samMethodName());
	assertEquals("()V", info.samMethodDesc());
}
```

The full code example can be found on [github](https://github.com/ruediste/lambda-inspector). Stay tuned for a follow up on how to get information out of this implementation method.
