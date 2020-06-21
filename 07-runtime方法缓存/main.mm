//
//  main.m
//  07-runtime方法缓存
//
//  Created by 刘光强 on 2020/2/7.
//  Copyright © 2020 guangqiang.liu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MJClassInfo.h"
#import "Person.h"
#import "Student.h"
#import "GoodStudent.h"

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
