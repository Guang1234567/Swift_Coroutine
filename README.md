# Swift_Coroutine

Base on [boostorg/context](https://github.com/boostorg/context).

API like [Kotlin/kotlinx.coroutines](https://github.com/Kotlin/kotlinx.coroutines/blob/master/docs/basics.md)

> Note:
>
> Chinese doc: [hltj/kotlinx.coroutines-cn](https://github.com/hltj/kotlinx.coroutines-cn/blob/master/docs/basics.md)

One of project's goal is study `Coroutine` api just once and built for the convenience of the developer from the Java Ecosystem (e.g Java-Web Android ...)

> Note: 
>
> The project can run in Android though it implement by Swift !

API also like Golang maybe maybe maybe.

## Background

Just want to reimplement it again. Swift Ecosystem maybe need `Coroutine` ^_^.

Thanks [boostorg/context](https://github.com/boostorg/context) for making `Coroutine` possible in C C++ and Swift.

And i donot known the assembly programing language, so thanks [boostorg/context](https://github.com/boostorg/context) again, ^_^.


Of course `#include <setjmp.h>` api in std-c can also achieve it. 

e.g [belozierov/SwiftCoroutine](https://github.com/belozierov/SwiftCoroutine)

**Related Project:**

- [Guang1234567/Swift_Boost_Context](https://github.com/Guang1234567/Swift_Boost_Context) :  A swift wrapper of [boostorg/context](https://github.com/boostorg/context)

## Support

- Android
- MacOS
- Ios
- Linux 

For web app, maybe modify the web framework (e.g [vapor/vapor](https://github.com/vapor/vapor)) to base on `Coroutine` just like [ktorio/ktor](https://github.com/ktorio/ktor) in future.

- Windows 

Not support now, maybe after swift-toolchain-5.3 and the windows ABI stable

## Usage

API just like [Kotlin/kotlinx.coroutines](https://github.com/Kotlin/kotlinx.coroutines/blob/master/docs/basics.md) but little different. After all, the `extension function`'s syntax not different between `Swift` and `Kotlin`.

```swift
//other ing ...
```

