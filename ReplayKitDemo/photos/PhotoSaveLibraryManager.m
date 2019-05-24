//
//  PhotoSaveLibraryManager.m
//  ReplayKitDemo
//
//  Created by ydd on 2019/5/24.
//  Copyright © 2019 ydd. All rights reserved.
//

#import "PhotoSaveLibraryManager.h"
#import <Photos/Photos.h>

NSString *const MYALBUM = @"ydd";

@implementation PhotoSaveLibraryManager


+ (void)saveImage:(UIImage *)image toMyAlbumCompletionHandler:(void(^)(BOOL success))completionHandler
{
    [self saveImage:image toAlbum:MYALBUM completionHandler:completionHandler];
}

+ (void)saveImage:(UIImage *)image toAlbum:(nullable NSString *)albumName completionHandler:(void(^)(BOOL success))completionHandler
{
    [self requestPhotoAuthorizationBlock:^(BOOL hasAuthorize) {
        if (hasAuthorize) {
            [self saveImages:@[image] toAlbum:albumName completionHandler:completionHandler];
        } else {
            NSLog(@"用户拒绝访问相册");
        }
    }];
    
}

+ (void)saveImages:(NSArray<UIImage *>*)images toAlbum:(nullable NSString *)albumName completionHandler:(void(^)(BOOL success))completionHandler
{
    [self requestPhotoAuthorizationBlock:^(BOOL hasAuthorize) {
        if (hasAuthorize) {
            [self photoSaveImages:images toAlbum:albumName completionHandler:completionHandler];
        } else {
            NSLog(@"用户拒绝访问相册");
        }
    }];
}

+ (void)photoSaveImages:(NSArray<UIImage *> *)images toAlbum:(NSString *)albumName completionHandler:(void (^)(BOOL))completionHandler {
    NSMutableArray <NSString*>* identifierArr = [NSMutableArray array];
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [images enumerateObjectsUsingBlock:^(UIImage * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:obj];
            NSString *localIdentifier = request.placeholderForCreatedAsset.localIdentifier;
            if (localIdentifier) {
                [identifierArr addObject:localIdentifier];
            }
        }];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            [self saveImagesWithIdentifierArr:identifierArr toAlbumName:albumName];
        }
        if (completionHandler) {
            completionHandler(NO);
        }
    }];
}


+ (void)saveImagesWithIdentifierArr:(NSArray <NSString*>*)identifierArr toAlbumName:(nullable NSString *)albumName {
    if (identifierArr.count == 0) {
        return;
    }
    if (!albumName) {
        return;
    }
    PHAssetCollection *collection = nil;
    if (albumName && albumName.length > 0) {
        collection = [self createPhotoWithAlbumName:albumName];
    }
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHFetchResult *assets = [PHAsset fetchAssetsWithLocalIdentifiers:identifierArr options:nil];
        [[PHAssetCollectionChangeRequest changeRequestForAssetCollection:collection] addAssets:assets];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"存入相册成功");
        }
    }];
}

+ (void)saveImageWithPath:(NSString *)path albumName:(nullable NSString *)albumName completionHandler:(void(^)(BOOL success))completionHandler
{
    [self requestPhotoAuthorizationBlock:^(BOOL hasAuthorize) {
        if (hasAuthorize) {
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            if (image) {
                [self saveImage:image toAlbum:albumName completionHandler:^(BOOL success) {
                    completionHandler(success);
                }];
            } else {
                completionHandler(NO);
            }
        } else {
            NSLog(@"用户拒绝访问相册");
        }
    }];
    
}

+ (void)requestPhotoAuthorizationBlock:(void(^)(BOOL hasAuthorize))block
{
    //判断授权状态
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized) {
        //已授权
        if (block) {
            block(YES);
        }
    } else if (status == PHAuthorizationStatusNotDetermined) {
        // 弹框请求用户授权
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                if (block) {
                    block(YES);
                }
            }
        }];
    } else {
        if (block) {
            block(NO);
        }
    }
}

+ (nullable PHAssetCollection *)createPhotoWithAlbumName:(NSString *)albumName
{
    //从已经存在的相簿中查找应用对应的相册
    PHFetchResult <PHAssetCollection *>*assetCollections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    for (PHAssetCollection *collection in assetCollections) {
        if ([collection.localizedTitle isEqualToString:albumName]) {
            return collection;
        }
    }
    // 没找到，就创建新的相簿
    NSError *error;
    __block NSString *assetCollectionLocalIdentifier = nil;
    // 这里用wait请求，保证创建成功相册后才保存进去
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        assetCollectionLocalIdentifier = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:albumName].placeholderForCreatedAssetCollection.localIdentifier;
        
    } error:&error];
    
    if(error) return nil;
    
    return [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[assetCollectionLocalIdentifier] options:nil].lastObject;
}

+ (void)saveVideo:(NSURL *)videoUrl toAlbumName:(nullable NSString *)albumName completionHandler:(void(^)(BOOL success))completionHandler
{
    
    [self requestPhotoAuthorizationBlock:^(BOOL hasAuthorize) {
        if (hasAuthorize) {
            __block NSString *localIdentifier=nil;
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                PHAssetChangeRequest*changeRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoUrl];
                PHObjectPlaceholder *placeholderAsset = changeRequest.placeholderForCreatedAsset;
                localIdentifier = placeholderAsset.localIdentifier;
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (success) {
                    [self saveVideoToAlbum:albumName localIdentifier:localIdentifier completionHandler:completionHandler];
                } else {
                    if (completionHandler) {
                        completionHandler(NO);
                    }
                }
            }];
            
        } else {
           NSLog(@"用户拒绝访问相册");
        }
    }];
}

+ (void)saveVideoToAlbum:(nullable NSString *)albumName localIdentifier:(nullable NSString *)localIdentifier completionHandler:(void(^)(BOOL success))completionHandler
{
    if (!localIdentifier) {
        return;
    }
    if (!albumName) {
        return;
    }
    
    PHAssetCollection *collection = nil;
    if (albumName && albumName.length > 0) {
        collection = [self createPhotoWithAlbumName:albumName];
    }
    
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        
        PHAsset *asset = [[PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil] lastObject];
        [[PHAssetCollectionChangeRequest changeRequestForAssetCollection:collection] addAssets:@[asset]];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"存入相册成功");
        }
        completionHandler(success);
    }];
}




@end
