---
layout: post
title:  "Caching Class Information"
date:   2017-03-06 +0100
categories: java
---
A use case that arises frequently when working on reflection based libraries is how to cache class related data structures once they are constructed. In this post I'll show an approach that does not lead to classloader memory leaks.

First lets setup the test harness to compare the different approaches. First, the interface of the store:

``` java
public interface ClassInfoStore<T> {
  T get(Class<?> cls);
  void store(Class<?> cls, T value);
}
```

Next we need a separate `ClassLoader` which loads a class. This allows to load a class and then drop all references to the class and the classloader. When triggering a garbage collection afterwards this causes the class to be collected.

Finally, the structure of our test:

``` java
// create a class information store
ClassInfoStore<String> store = new HashMapClassInfoStore<>();

// load a class with a separate class loader
Class<?> a = load(A.class);

// store some data
store.store(a, "Hello World");

// create a weak reference which will turn null as
// soon as the class is garbage collected
WeakReference<Class<?>> ref = new WeakReference<Class<?>>(a);

// clear the reference to the class and perform a GC
a = null;
System.gc();

// check that the class has been unloaded
assertNull(ref.get());
```

In the rest of the post we will change the store implementation and the data structures stored.

## Hash Map
The first approach that comes to mind is to simply use a `HashMap` with the classes as key and whatever data required as value. This leads to the following situation:

![Hashmap]({{ site.baseurl }}/diagrams/caching-class-information/hashmap.png)

This will keep the class referenced for ever, resulting in a memory leak. This is confirmed by the test in the previous section.

## Weak HashMap
By replacing the `HashMap` with a `WeakHashMap` the strong reference to the class is avoided, allowing garbage collection of the latter.

``` java
private Map<Class<?>, T> store = new WeakHashMap<>();
```

This is confirmed by the test. However we are not done: usually the information contained in the store references the class:

![Information References Class]({{ site.baseurl }}/diagrams/caching-class-information/infoReferencecClass.png)

Adding this reference breaks the test again. You might be tempted to simply add a weak reference in the store:

![Information References Class]({{ site.baseurl }}/diagrams/caching-class-information/weakRef.png)

``` java
public class WeakRefClassInfoStore<T> implements ClassInfoStore<T> {

    private Map<Class<?>, WeakReference<T>> store = new WeakHashMap<>();

    @Override
    public T get(Class<?> cls) {
        WeakReference<T> ref = store.get(cls);
        if (ref == null)
            return null;
        return ref.get();
    }

    @Override
    public void store(Class<?> cls, T value) {
        store.put(cls, new WeakReference<>(value));
    }
}
```
Unfortunately there is no more strong reference to the information in the store! Thus after the first GC the information will be gone:

``` java
// create a class information store
 ClassInfoStore<Info> store = new WeakRefClassInfoStore<>();

 // load a class with a separate class loader
 Class<?> a = load(A.class);

 // store some data
 Info info = new Info();
 info.field = a.getDeclaredField("value");
 store.store(a, info);
 assertNotNull(store.get(a));


 // clear the reference to the info and perform a GC
 info = null;
 System.gc();

 // Fails. Information has been GCed
 assertNotNull(store.get(a));
```

## The Final Solution
We have seen that weak references alone won't save the day. But fortunately there is another approach: Make the class loader reference the cache. Since a classloader references all it's classes, in order for a class to become eligible for collection, the classloader has to be eligible for collection as well. Thus our approach does not create memory leaks. But how to make the classloader reference our cache?

This can be achieved by invoking the class loaders protected `defineClass()`-method directly via reflection to inject a helper class into the classloader. The helper class has a static field which will be initialized to our store. Afterwards we can use weak references to quickly lookup our cache and the cached values. So the final design is

![Information References Class]({{ site.baseurl }}/diagrams/caching-class-information/finalApproach.png)

The intermediary step over `infoMaps` allows multiple store instances to coexist with a single helper class.

We'll dig through it step by step. First the helper class:

``` java
public static class StoreHelper {
    public static Object infoMaps;
}
```

Then the get method, which is simple due to the `infoLookup`:

``` java
public T get(Class<?> cls) {
	WeakReference<T> ref = infoLookup.get(cls);
	if (ref == null)
  	return null;
	else
    return ref.get();
}
```

And the setter method, which is a bit more complex:

``` java
public void store(Class<?> cls, T value) {
  ClassLoader loader = cls.getClassLoader();

  WeakReference<InfoMap<?>> infoMapRef = infoMapLookup.get(loader);
  InfoMap<T> infoMap;
  if (infoMapRef == null) {
      infoMap = new InfoMap<>();
      getInfoMaps(loader).put(this, infoMap);
      infoMapLookup.put(loader, new WeakReference<FinalStore.InfoMap<?>>(infoMap));
  } else {
      infoMap = (InfoMap<T>) infoMapRef.get();
  }

  infoMap.put(cls, value);
  infoLookup.put(cls, new WeakReference<>(value));
}
```

And finally the method which manages the helper.

``` java
private Map<FinalStore<?>, InfoMap<?>> getInfoMaps(ClassLoader loader) {
    // get info maps
    WeakReference<Map<FinalStore<?>, InfoMap<?>>> infoMapsRef = FinalStore.infoMapsLookup.get(loader);
    Map<FinalStore<?>, InfoMap<?>> infoMaps;
    if (infoMapsRef == null) {
        try {
            Class<?> helperCls = (Class<?>) defineClassMethod.invoke(loader, StoreHelper.class.getName(),
                    helperBytecode, 0, helperBytecode.length);
            Field field = helperCls.getField("infoMaps");
            infoMaps = new WeakHashMap<>();
            field.set(null, infoMaps);
            FinalStore.infoMapsLookup.put(loader, new WeakReference<Map<FinalStore<?>, InfoMap<?>>>(infoMaps));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    } else
        infoMaps = infoMapsRef.get();
    return infoMaps;
}
```

That's it, the tests pass. Please note that the whole sample is not thread safe. A few well placed `synchronized` statements would handle this. As always, the full source code can be found on [github](https://github.com/ruediste/blog-samples/tree/master/src/main/java/com/github/ruediste/blogSamples/classInfo)
