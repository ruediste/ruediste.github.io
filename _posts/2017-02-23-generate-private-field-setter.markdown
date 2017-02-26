---
layout: post
title:  "Dynamically Generate Setters Classes for Private Fields"
date:   2017-02-23 06:33:54 +0100
categories: bytecode
---

In this post we'll discuss how to generate setter classes for private fields of another class.

There are several ways to access private fields of a class: The first that comes to mind is good old java reflection. For more performance you can generate code using `invokedynamic` with method handles. But there is a third way, used by the JRE to generate classes for lambda methods: `Unsave.defineAnonymousClass()`. Anonymous classes have a host class. They use the same classloader and have the same access to class members. But the classloader does not reference the anonymous class. Therefore as soon as the last reference to the class is removed, the class can be garbage collected. And you don't have to care about name clashes.

So, let's build a sample setter for the following class:

``` java
public class Sample {
    private String message;
    public String getMessage() {
        return message;
    }
}
```

First we define an interface for the setter:

``` java
public interface SampleSetter {
    void setMessage(Sample sample, String message);
}
```

As we don't want to write the whole bytecode of the setter class, we'll make the field temporarily public and implement the setter class in plain old Java:

``` java
public class SampleSetterImpl implements SampleSetter {
    public void setMessage(Sample sample, String message) {
         sample.message = message;
    }
}
```

We'll use [ASM](http://asm.ow2.org/index.html) to do the bytecode generation. Using the excellent [ASM Bytecode Eclipse Plugin](http://asm.ow2.org/eclipse/index.html) we can directly retrieve the code needed to generate the setter implementation. Just open the `Bytecode` view in Eclipse, switch it to ASM mode (icon in the top right of the view) and copy past the code:

``` java
public static byte[] dump() throws Exception {

	ClassWriter cw = new ClassWriter(0);
	MethodVisitor mv;

	cw.visit(V1_5, ACC_PUBLIC + ACC_SUPER, "generated", null, "java/lang/Object",
	        new String[] { "com/github/ruediste/privateFieldCodegen/SampleSetter" });

	{
	    mv = cw.visitMethod(ACC_PUBLIC, "<init>", "()V", null, null);
	    mv.visitCode();
	    mv.visitVarInsn(ALOAD, 0);
	    mv.visitMethodInsn(INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false);
	    mv.visitInsn(RETURN);
	    mv.visitMaxs(1, 1);
	    mv.visitEnd();
	}
	{
	    mv = cw.visitMethod(ACC_PUBLIC, "setMessage",
	            "(Lcom/github/ruediste/privateFieldCodegen/Sample;Ljava/lang/String;)V", null, null);
	    mv.visitCode();
	    mv.visitVarInsn(ALOAD, 1);
	    mv.visitVarInsn(ALOAD, 2);
	    mv.visitFieldInsn(PUTFIELD, "com/github/ruediste/privateFieldCodegen/Sample", "message",
	            "Ljava/lang/String;");
	    mv.visitInsn(RETURN);
	    mv.visitMaxs(2, 3);
	    mv.visitEnd();
	}
	cw.visitEnd();

	return cw.toByteArray();
	}
```

We see the class implementing the setter interface. The first method is the constructor, the second method is the `setMessage()` implementation. The `PUTFIELD` instruction is used to store the field value. It does not differentiate between public and private fields, so we can use the code as-is.

So the remaining task is to load the class:

``` java
public class AccessorGenerator {
    public static SampleSetter generate() {
	    Class<?> accessor = getUnsafe().defineAnonymousClass(Sample.class, dump(), null);
	    return (SampleSetter) accessor.newInstance();
    }
...		
```

So far, so simple, but what does `getUnsafe()` do? Since `sun.misc.Unsafe` is not part of the JRE Api there is intentionally no direct way to get an instance of it. One has to use reflection to get the static `theUnsafe` field of the class:

``` java
@SuppressWarnings("restriction")
private sun.misc.Unsafe getUnsafe() {
    try {
        Field unsafeField = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        return (Unsafe) unsafeField.get(null);
    } catch (Exception e) {
        throw new RuntimeException(e);
    }
}
```

Well, looks all good, right? But we miss a little test to show it all works out:

``` java
@Test
public void test() {
    Sample sample = new Sample();
    assertEquals(null, sample.getMessage());
    AccessorGenerator.generate().setMessage(sample, "Hello World");
    assertEquals("Hello World", sample.getMessage());
}
```

You can find the complete code sample on [github](https://github.com/ruediste/private-field-codegen)
