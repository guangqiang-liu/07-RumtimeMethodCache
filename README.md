# 07-Runtime方法缓存

OC中Runtime的基本概念：
> Runtime是OC中的运行时机制，之所以说OC是一门动态性语言，这也正是因为有Runtime机制，Runtime API底层源码大部分也都是使用c、c++和汇编实现

在前面的学习我们基本都了解到，OC的函数调用最终都转换为`Runtime`的消息发送机制，也就是调用底层函数`objc_msgSend()`，然而在使用`objc_msgSend()`进行消息发送时最为关键的就是要通过`isa`指针找到对应的类，然后找到对应的方法来发送消息，下面我们就再来了解下`isa`指针

底层源码查找路径：`objc4 搜索struct objc_object -> struct objc_object {} -> isa_t isa -> union isa_t{}`

通过底层源码查找，我们发现OC基类对象中的`isa`指针最终经过优化后，变成了`isa_t`共用体类型，其中核心源码如下：

```
union isa_t 
{
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls;
    uintptr_t bits;

# if __arm64__
	// 这里我们就只保留__arm64__环境
    struct {
        uintptr_t nonpointer        : 1;
        uintptr_t has_assoc         : 1;
        uintptr_t has_cxx_dtor      : 1;
        uintptr_t shiftcls          : 33; // MACH_VM_MAX_ADDRESS 0x1000000000
        uintptr_t magic             : 6;
        uintptr_t weakly_referenced : 1;
        uintptr_t deallocating      : 1;
        uintptr_t has_sidetable_rc  : 1;
        uintptr_t extra_rc          : 19;
    };
}
``` 

核心代码如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200206-205939@2x.png)

上面结构体内每一个元素的作用如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200206-210010@2x.png)

---

我们再来类对象的底层数据结构进行分析

`objc_class`class对象结构体

```
struct objc_class : objc_object {
    // Class ISA;
    
    Class superclass;
    
    // 方法缓存数据，所有的已调用过的方法都缓存在`bucket_t`结构体中
    cache_t cache;
    
    // 存储具体的类信息
    class_data_bits_t bits;
}
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-113725@2x.png)

`class_data_bits_t` & `MASK`得到`class_rw_t`结构体

```
struct class_rw_t {
    // Be warned that Symbolication knows the layout of this structure.
    uint32_t flags;
    uint32_t version;

    // ro_t中存储的是类初始化的信息
    const class_ro_t *ro;

    // 方法列表：[method_list_t, [method_list_t]]
    method_array_t methods;
    
    // 属性列表：[property_list_t, property_list_t]
    property_array_t properties;
    
    // 协议列表，[protocol_list_t, protocol_list_t]
    protocol_array_t protocols;

    Class firstSubclass;
    Class nextSiblingClass;

    char *demangledName;
}
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-113750@2x.png)

`class_ro_t`class初始化数据结构体，此结构体只读

```
struct class_ro_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif

    const uint8_t * ivarLayout;
    
    // 类名
    const char * name;
    
    // 方法列表：[method_t, method_t]
    method_list_t * baseMethodList;
    
    // 协议列表：[protocol_ref_t， protocol_ref_t]
    protocol_list_t * baseProtocols;
    
    // 成员变量列表：[ivar_t, ivar_t]
    const ivar_list_t * ivars;

    const uint8_t * weakIvarLayout;
    
    // 属性列表：[property_t, property_t]
    property_list_t *baseProperties;
}
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-113813@2x.png)

`method_t`:method对象的数据结构

```
struct method_t {
    // 函数名，类似于char *类型，理解为就是个字符串
    SEL name;
    
    // 函数编码，对应的值就是`TypeEncoding`拼接成的字符串
    const char *types;
    
    // 函数的内存地址，指向函数的指针，代表函数的具体实现
    IMP imp;
}
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-114007@2x.png)

`TypeEncoding`编码表如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-114023@2x.png)

`cache_t`方法缓存对象的数据结构：

```
struct cache_t {

    // 用于存储缓存方法的哈希表(散列表)
    struct bucket_t *_buckets;
    
    // 哈希表的长度 -1
    mask_t _mask;
    
    // 已经缓存的方法数量
    mask_t _occupied;
}
```

`bucket_t`缓存列表哈希表：

```
struct bucket_t {

    // SEL作为key，SEL也就是方法名
    cache_key_t _key;
    
    // 函数的内存地址，也就是指向函数的指针
    IMP _imp;
}
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-114429@2x.png)

下面我们创建一个示例工程来验证下方法缓存，示例代码如下：

`Person`类

```
@interface Person : NSObject

- (void)run;
- (void)eat;
@end


@implementation Person

- (void)run {
    NSLog(@"%s", __func__);
}

- (void)eat {
    NSLog(@"%s", __func__);
}
@end
```

`main`函数：

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        Person *person = [[Person alloc] init];
        xx_objc_class *cls = (__bridge xx_objc_class*)[Person class];
        
        [person run];
        NSLog(@"111");
        [person eat];
    }
    return 0;
}
```

我们查看对应的方法缓存打印如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-143144@2x.png)

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-143316@2x.png)

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-143437@2x.png)

接下来我们打印查看下`_buckets`哈希表中的存储的`bucket_t`，代码如下：

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        Person *person = [[Person alloc] init];
        
        xx_objc_class *personClass = (__bridge xx_objc_class*)[Person class];
        
        [person run];
        NSLog(@"111");
        [person eat];
        NSLog(@"----------");
        
        cache_t cache = personClass->cache;
        bucket_t *buckets = cache._buckets;
        for (NSInteger i = 0; i <= cache._mask; i ++) {
            bucket_t bucket = buckets[i];
            NSLog(@"%s--%p", bucket._key, bucket._imp);
        }
    }
    return 0;
}
```

打印如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-155134@2x.png)

我们在修改代码如下：

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        Person *person = [[Person alloc] init];
        xx_objc_class *personClass = (__bridge xx_objc_class*)[Person class];
        
        [person run];
        [person eat];
        [person test];
        [person work];
        NSLog(@"----------");
        
        cache_t cache = personClass->cache;
        bucket_t *buckets = cache._buckets;
        for (NSInteger i = 0; i <= cache._mask; i ++) {
            bucket_t bucket = buckets[i];
            NSLog(@"%s--%p", bucket._key, bucket._imp);
        }
        
        NSLog(@"33");
    }
    return 0;
}
```

查看打印结果如图1：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-160939@2x.png)

从图1我们可以看出，当我们执行完`work`方法后，方法缓存列表的容量变为之前的2倍了，长度为8，这是因为当执行完`test`函数后，方法缓存的数量就达到了最开始分配的4的长度，所以缓存列表长度扩容了一倍，需要注意：在缓存列表扩容后，就会清除掉之前已经缓存的方法，从新缓存

图2

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-161123@2x.png)

我们从图2的终端打印可以看出，此时缓存列表中只缓存了2个方法，`test`和`work`方法，因为执行完`test`方法后，缓存列表扩容，清除了之前缓存的方法

接下来我们来验证下从方法缓存列表哈希表中查找方法的过程，代码如下：

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        
        Person *person = [[Person alloc] init];
        xx_objc_class *personClass = (__bridge xx_objc_class*)[Person class];
        
        [person run];
        [person eat];
        [person test];
        [person work];
        NSLog(@"----------");
        
        cache_t cache = personClass->cache;
        bucket_t *buckets = cache._buckets;
        
        // 通过`@selector(work) & cache._mask`找到方法对应的下标索引index，然后在`buckets`中取出对应的`bucket_t`
        bucket_t workbucket = buckets[(long long)@selector(work) & cache._mask];
        NSLog(@"从哈希表中找方法：%s--%p", workbucket._key, workbucket._imp);
        NSLog(@"----------");
        
        for (NSInteger i = 0; i <= cache._mask; i ++) {
            bucket_t bucket = buckets[i];
            NSLog(@"%s--%p", bucket._key, bucket._imp);
        }
        NSLog(@"33");
    }
    return 0;
}
```

我们通过方法名`work`&`mask`得到一个索引，这个索引便是存储方法`work`在哈希表中的索引值，通过下图打印方法`work`的函数地址也可以看出，`@selector(work)&mask`取出的方法正好就是缓存列表中的`work`方法

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-162746@2x.png)

我们在看一个继承关系中，方法调用时的缓存策略，当子类调用父类的方法时，这时方法是缓存在子类中还是缓存在父类中尼，代码如下：

```
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
    
        Student *student = [[Student alloc] init];
        xx_objc_class *studentClass = (__bridge xx_objc_class*)[Student class];
        [student run];

        cache_t cache2 = studentClass->cache;
        bucket_t *buckets2 = cache2._buckets;
        
        for (NSInteger i = 0; i <= cache2._mask; i ++) {
            bucket_t bucket = buckets2[i];
            NSLog(@"%s--%p", bucket._key, bucket._imp);
        }
        
        NSLog(@"--------------");
        
        Person *person = [[Person alloc] init];
        xx_objc_class *personClass = (__bridge xx_objc_class*)[Person class];
        cache_t cache = personClass->cache;
        bucket_t *buckets = cache._buckets;

        for (NSInteger i = 0; i <= cache._mask; i ++) {
            bucket_t bucket = buckets[i];
            NSLog(@"%s--%p", bucket._key, bucket._imp);
        }
        
        NSLog(@"---");
    }
    return 0;
}
```

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-165949@2x.png)

我们从上图的打印可以得出结论，当子类调用父类的方法时，这时这个方法只会缓存在`调用者`的类对象中，也就是说只会缓存在子类中，并不会缓存到父类对象中

OC方法缓存中哈希表(散列表)设计原理如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200207-174519@2x.png)


讲解示例Demo地址：[https://github.com/guangqiang-liu/07-RumtimeMethodCache]()


## 更多文章
* ReactNative开源项目OneM(1200+star)：**[https://github.com/guangqiang-liu/OneM](https://github.com/guangqiang-liu/OneM)**：欢迎小伙伴们 **star**
* iOS组件化开发实战项目(500+star)：**[https://github.com/guangqiang-liu/iOS-Component-Pro]()**：欢迎小伙伴们 **star**
* 简书主页：包含多篇iOS和RN开发相关的技术文章[http://www.jianshu.com/u/023338566ca5](http://www.jianshu.com/u/023338566ca5) 欢迎小伙伴们：**多多关注，点赞**
* ReactNative QQ技术交流群(2000人)：**620792950** 欢迎小伙伴进群交流学习
* iOS QQ技术交流群：**678441305** 欢迎小伙伴进群交流学习