#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Führt `block` aus und fängt dabei Objective-C-Exceptions ab, die Swift selbst nicht fangen kann
/// (z. B. von AVFoundation oder Core Animation). Gibt die Exception zurück, sonst nil.
NSException * _Nullable ObjCTry(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
