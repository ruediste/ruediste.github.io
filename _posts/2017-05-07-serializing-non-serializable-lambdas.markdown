---
layout: post
title:  "Serializing Non-Serializable Lambdas"
date:   2017-05-07 +0100
categories: [java, kryo]
---
Standard Java serializiation of lambda expressions isn't straight forward, but well understood. But the mechanism only works if the functional interface implements `Serializable`. When using alternative serialization libraries such as [Kryo](https://github.com/EsotericSoftware/kryo), there is typically no need to inherit from `Serializable`. Unfortunately I haven't seen a solution yet to apply the same principle to lambdas.

For lambdas of functional interfaces which extend `Serializable`, there is the `ClosureSerializer` for Kyro. It works by invoking the `writeReplace()` function of the lambda to obtain a `SerializedLambda` which is then serialized. For deserialization the `SerializedLambda` is instantiated and the `readResolve()` method is invoked, resulting in the construction of the corresponding lambda. If the lambda is non-serializable, two key parts are missing: first the `writeReplace()` method is not present and second the `readResolve()` method does not work, as it depends on the synthetic `$deserializeLambda$()`-method created by the compiler in the class declaring the lambda.

For the `writeReplace()` function to be generated we can reuse a technique introduced in [a previous post:]({{ site.baseurl }}/bytecode/2017/02/25/lambda-inspection.html) the 'InnerClassLambdaMetafactory', responsible to generate the lambda classes, is simply patched to always treat the lambda as serializalbe and thus create the required method. This is simply achieved by overriding a constructor argument:

``` java
public class LambdaFactoryAgent {
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

    private static final class InnerClassLambdaMetafactoryTransformer implements ClassFileTransformer {
        @Override
        public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
            if (className.equals("java/lang/invoke/InnerClassLambdaMetafactory")) {
                ClassReader cr = new ClassReader(classfileBuffer);
                ClassWriter cw = new ClassWriter(cr, 0);
                cr.accept(new ClassVisitor(Opcodes.ASM5, cw) {
                    @Override
                    public MethodVisitor visitMethod(int access, String name, String desc, String signature,
                            String[] exceptions) {
												// only modify the (only) constructor
                        if ("<init>".equals(name)) {
                            return new MethodVisitor(Opcodes.ASM5,
                                    super.visitMethod(access, name, desc, signature, exceptions)) {
                                @Override
                                public void visitCode() {
                                    super.visitCode();
                                    // set the isSerializable-parameter to true
                                    mv.visitInsn(Opcodes.ICONST_1);
                                    mv.visitVarInsn(Opcodes.ISTORE, 7);
                                };
                            };
                        } else
                            return super.visitMethod(access, name, desc, signature, exceptions);
                    }
                }, 0);
                return cw.toByteArray();
            }
            return null;
        }
    }
}
```

Remains the instantiation of the lambda from the `SerializedLambda`: Here we perform the invocation of the `LambdaMetafactory` directly instead of relying on the generated `$deserializeLambda$()` method. This is possible by simply extracting the required parameters from the `SerializedLambda`, invoking the meta factory and calling the resulting call site:

``` java
SerializedLambda lambda = ...;
Class<?> capturingClass = (Class<?>) capturingClassGetter.invoke(lambda);
ClassLoader cl = capturingClass.getClassLoader();
Class<?> implClass = cl.loadClass(lambda.getImplClass().replace('/', '.'));
Class<?> interfaceType = cl.loadClass(lambda.getFunctionalInterfaceClass().replace('/', '.'));
Lookup lookup = getLookup(implClass);
MethodType implType = MethodType.fromMethodDescriptorString(lambda.getImplMethodSignature(),
        cl);
MethodType samType = MethodType
        .fromMethodDescriptorString(lambda.getFunctionalInterfaceMethodSignature(), null);

MethodHandle implMethod;
boolean implIsInstanceMethod = true;
switch (lambda.getImplMethodKind()) {
case MethodHandleInfo.REF_invokeInterface:
case MethodHandleInfo.REF_invokeVirtual:
    implMethod = lookup.findVirtual(implClass, lambda.getImplMethodName(), implType);
    break;
case MethodHandleInfo.REF_invokeSpecial:
    implMethod = lookup.findSpecial(implClass, lambda.getImplMethodName(), implType, implClass);
    break;
case MethodHandleInfo.REF_invokeStatic:
    implMethod = lookup.findStatic(implClass, lambda.getImplMethodName(), implType);
    implIsInstanceMethod = false;
    break;
default:
    throw new RuntimeException("Unsupported impl method kind " + lambda.getImplMethodKind());
}

// determine type of factory
MethodType factoryType = MethodType.methodType(interfaceType, Arrays.copyOf(
        implType.parameterArray(), implType.parameterCount() - samType.parameterCount()));
if (implIsInstanceMethod)
    factoryType = factoryType.insertParameterTypes(0, implClass);


// determine type of method with implements the SAM
MethodType instantiatedType = implType;
if (implType.parameterCount() > samType.parameterCount())
	 instantiatedType = implType.dropParameterTypes(0,
					 implType.parameterCount() - samType.parameterCount());

// call factory
CallSite callSite = LambdaMetafactory.altMetafactory(lookup,
        lambda.getFunctionalInterfaceMethodName(), factoryType, samType, implMethod, instantiatedType, 1);

// invoke callsite
Object[] capturedArgs = new Object[lambda.getCapturedArgCount()];
for (int i = 0; i < lambda.getCapturedArgCount(); i++) {
    capturedArgs[i] = lambda.getCapturedArg(i);
}
return callSite.dynamicInvoker().invokeWithArguments(capturedArgs);
```

With this functionality in place, it is easy to make Kryo support non-serializable lambdas:

``` java
kryo.register(java.lang.invoke.SerializedLambda.class);
kryo.register(ClosureSerializer.Closure.class, new ClosureSerializer() {
	 @Override
	 public Object read(Kryo kryo, Input input, Class type) {
			 try {
					 SerializedLambda lambda = kryo.readObject(input, SerializedLambda.class);
					 ...
				 } catch (Throwable e) {
				 throw new RuntimeException(e);
		 }
 };
});
```
Of course, the agent has to be loaded during application startup:

``` java
AgentLoader.loadAgentClass(LambdaFactoryAgent.class.getName(), "");
```

That's it, you are now ready to use lambdas without `(Runnable & Serializable) ()->{...}` - workarounds. I'm using this technique together with Hazelcast for distributed execution.
