---
layout: post
title:  "(De)Serializing Polymorphic Types from/to Json with Gson"
date:   2020-04-29 +0100
categories: [java, gson]
---
In Json objects are simply represented as a bunch of properties. When deserializing an object graph, the type information is recovered using the property types of the java types. Consider the following classes:

``` java
class A { int valueA; B b;}
class B {int valueB; }
```

when deserializing the following json value

``` json
{ "valueA": 1, "b": {"valueB": 2}}
```

it is clear that an instance of `B` has to be instantiated, due to the type of the field `b` of `A`.

Unfortunately this approach breaks down as soon as type hierarchies enter the scene:

``` java
public class Referencing {
    Base base;
    SubClassA a;
}

abstract class Base { }

class SubClassA extends Base { }
class SubClassB extends Base { }
```

consider the following snippet:

```
{"base": {"baseField": 2}}
```

Since `Base` is abstract, it is clear that either `SubClassA` or `SubClassB` has to be instantiated for the `base` field of `Referencing`. But there is no way to know which. The type information was lost during serialization.

# Adding type information to Json
Over time a few approaches to add the type information to the json data have been invented:
* Array: the object is wrapped in an array. The first element represents the type, the second element is the object itself:
```
{"base": ["SubClassA", {"baseField": 2}]}
```
* Property: the object is wrapped in another object, using a property name representing the type:
```
{"base": {"SubClassA": {"baseField": 2}}}
```
Used in the [ElasticSearch query DSL](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html).
* Type Property: a property is added to the object, representing the type:
``` json
{"base": {"@type": "SubClassA", "baseField": 2}}
```

# Representing types
The next choice is how to represent types. One option is to use the fully qualified Java type name. While this simplifies deserialization, it makes refactoring hard, since every change of package or renames renders already serialized data unusable.

The other approach is to use a shorter string, typically the simple class name only (without package). The downside is that the types have to be registered with or discovered by the deserializer.

# Implementing polymorphic serialization with Gson
First we have to decide how to configure the deserializer. Some [exiting solutions](https://stackoverflow.com/questions/19588020/gson-serialize-a-list-of-polymorphic-objects) require to explicitly register all subclasses, but we'll go for classpath scanning. To enable polymorphic serialization the `@GsonPolymorph` annotation is created and added to the base class. Only fields of the base types will be serialized in a polymorphic style. The type representation is typically the simple class name, converted to lower camel, but can be customized using `@GsonPolymorphName`. For refactoring/migration scenarios, additional names can be assigned to a class using `@GsonPolymorphAltName`. These names are only used for deserialization.

Support is added to Gson using a `TypeAdapterFactory`:
``` java
public class GsonPolymorphAdapter implements TypeAdapterFactory {
    ...
}
```

In the constructor the classpath is scanned:

``` java
public GsonPolymorphAdapter(PolymorphStyle style, ClassLoader cl, String pkg) {
    this.style = style;

    // scan the classpath
    try (var scanResult = new ClassGraph().enableClassInfo().enableAnnotationInfo().whitelistPackages(pkg).scan()) {

        // iterate over classes annotated with @GsonPolymorph
        for (ClassInfo baseClassInfo : scanResult.getClassesWithAnnotation(GsonPolymorph.class.getName())) {
            // build a map of all names of subclasses to the subclass
            var nameMap = new HashMap<String, Class<?>>();

            // add the names of the base class as well to simplify the deserializer
            var baseClass = cl.loadClass(baseClassInfo.getName());
            getNames(baseClass).forEach(name -> nameMap.put(name, baseClass));

            // iterate over subclasses
            for (var subClassInfo : baseClassInfo.getSubclasses()) {
                var subClass = cl.loadClass(subClassInfo.getName());
                for (var name : getNames(subClass)) {
                    var existingClass = nameMap.put(name, subClass);
                    if (existingClass != null) {
                        throw new RuntimeException("Subclasses " + subClass + " and " + existingClass + " of "
                                + baseClassInfo + " map to the same name " + name);
                    }
                }
            }
            classesByName.put(baseClass, nameMap);
        }
    } catch (ClassNotFoundException e) {
        throw new RuntimeException(e);
    }
}
```

Whenever a type annotated with `@GsonPolymorph` is encountered, a type adapter is instantiated:
``` java
public <T> TypeAdapter<T> create(Gson gson, TypeToken<T> type) {

    if (type.getRawType().isAnnotationPresent(GsonPolymorph.class)) {
        var classMap = classesByName.get(type.getRawType());
        if (classMap == null)
            throw new RuntimeException("Base class " + type.getRawType() + " was not scanned");

        // collect TypeAdapters for all subclasses
        Map<Class<?>, TypeAdapter> adapterByClass = new HashMap<>();
        Map<String, TypeAdapter> adapterByName = new HashMap<>();
        classMap.forEach((name, cls) -> {
            TypeAdapter t;
            if (cls == type.getRawType())
                t = gson.getDelegateAdapter(this, type);
            else
                t = gson.getAdapter(cls);
            adapterByClass.put(cls, t);
            adapterByName.put(name, t);
        });

        return new TypeAdapter<T>() {

            @Override
            public void write(JsonWriter out, T value) throws IOException {
                if (value == null) {
                    out.nullValue();
                    return;
                }

                String name = getName(value.getClass());
                switch (style) {
                case PROPERTY: {
                    out.beginObject();

                    out.name(name);
                    adapterByClass.get(value.getClass()).write(out, value);
                    out.endObject();
                }
                    break;
                ...
                }

            }

            @Override
            public T read(JsonReader in) throws IOException {
                if (in.peek() == JsonToken.NULL) {
                    in.nextNull();
                    return null;
                }

                switch (style) {
                case PROPERTY: {
                    in.beginObject();
                    String name = in.nextName();
                    var result = getAdapter(adapterByName, name, type).read(in);
                    in.endObject();
                    return (T) result;
                }
                ...
                }

            }

            private TypeAdapter getAdapter(Map<String, TypeAdapter> adapterByName, String name, TypeToken<T> type) {
                TypeAdapter result = adapterByName.get(name);
                if (result == null) {
                    throw new RuntimeException("Unknown sub type " + name + " of type " + type);
                }
                return result;
            }
        };
    }
    return null;
}
```

And that's basically it. Full source code can be found on [github](https://github.com/ruediste/blog-samples/tree/master/src/main/java/com/github/ruediste/blogSamples/gsonPolymorphism).