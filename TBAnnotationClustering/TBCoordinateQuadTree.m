//
//  TBCoordinateQuadTree.m
//  TBAnnotationClustering
//
//  Created by Theodore Calmes on 9/27/13.
//  Copyright (c) 2013 Theodore Calmes. All rights reserved.
//

#import "TBCoordinateQuadTree.h"
#import "TBClusterAnnotation.h"

typedef struct TBHotelInfo {
    char* hotelName;
    char* hotelPhoneNumber;
} TBHotelInfo;

TBBoundingBox TBBoundingBoxForMapRect(MKMapRect mapRect)
{
    CLLocationCoordinate2D topLeft = MKCoordinateForMapPoint(mapRect.origin);
    CLLocationCoordinate2D botRight = MKCoordinateForMapPoint(MKMapPointMake(MKMapRectGetMaxX(mapRect), MKMapRectGetMaxY(mapRect)));
    
    CLLocationDegrees minLat = botRight.latitude;
    CLLocationDegrees maxLat = topLeft.latitude;
    
    CLLocationDegrees minLon = topLeft.longitude;
    CLLocationDegrees maxLon = botRight.longitude;
    
    return TBBoundingBoxMake(minLat, minLon, maxLat, maxLon);
}

MKMapRect TBMapRectForBoundingBox(TBBoundingBox boundingBox)
{
    MKMapPoint topLeft = MKMapPointForCoordinate(CLLocationCoordinate2DMake(boundingBox.x0, boundingBox.y0));
    MKMapPoint botRight = MKMapPointForCoordinate(CLLocationCoordinate2DMake(boundingBox.xf, boundingBox.yf));
    
    return MKMapRectMake(topLeft.x, botRight.y, fabs(botRight.x - topLeft.x), fabs(botRight.y - topLeft.y));
}

NSInteger TBZoomScaleToZoomLevel(MKZoomScale scale)
{
    double totalTilesAtMaxZoom = MKMapSizeWorld.width / 256.0;
    NSInteger zoomLevelAtMaxZoom = log2(totalTilesAtMaxZoom);
    NSInteger zoomLevel = MAX(0, zoomLevelAtMaxZoom + floor(log2f(scale) + 0.5));
    
    return zoomLevel;
}

float TBCellSizeForZoomScale(MKZoomScale zoomScale)
{
    NSInteger zoomLevel = TBZoomScaleToZoomLevel(zoomScale);
    
    switch (zoomLevel) {
        case 13:
        case 14:
        case 15:
            return 64;
        case 16:
        case 17:
        case 18:
            return 32;
        case 19:
            return 16;
            
        default:
            return 88;
    }
}

@implementation TBCoordinateQuadTree

- (void)buildTree
{
    @autoreleasepool {
        NSString *data = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"USA-HotelMotel" ofType:@"csv"] encoding:NSASCIIStringEncoding error:nil];
        NSArray *lines = [data componentsSeparatedByString:@"\n"];
        
        NSInteger count = lines.count - 1;
        
        NSMutableArray *coordArray = [[NSMutableArray alloc] init];
        for (NSInteger i = 0; i < count; i++) {
            NSArray *components = [lines[i] componentsSeparatedByString:@","];
            double latitude = [components[1] doubleValue];
            double longitude = [components[0] doubleValue];
            NSString *hotelName = [components[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [coordArray addObject:[NSArray arrayWithObjects:[NSNumber numberWithFloat:latitude], [NSNumber numberWithFloat:longitude], hotelName, nil]];
        }
        
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSInteger i = 0; i < count; i++) {
            NSNumber *latitudeN = [[coordArray objectAtIndex:(NSUInteger) i] objectAtIndex:0];
            NSNumber *longitudeN = [[coordArray objectAtIndex:(NSUInteger) i] objectAtIndex:1];
            double latitude = [latitudeN floatValue];
            double longitude = [longitudeN floatValue];
            
            CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
            NSValue *coordinateValue = [NSValue valueWithBytes:&coordinate objCType:@encode(CLLocationCoordinate2D)];
            
            NSMutableArray *annotationsAtLocation = result[coordinateValue];
            if (!annotationsAtLocation) {
                annotationsAtLocation = [NSMutableArray array];
                result[coordinateValue] = annotationsAtLocation;
            }
            NSNumber *dataId = [NSNumber numberWithInt:i];
            [annotationsAtLocation addObject:dataId];
        }
        
        for (id key in result) {
            NSArray *coordinates = [result objectForKey:key];
            if(coordinates.count > 1) {
                double distance = 20 * coordinates.count / 2.0;
                double radiansBetweenAnnotations = (M_PI * 2) / coordinates.count;
                
                for (int i = 0; i < coordinates.count; i++) {
                    int dataId = [[coordinates objectAtIndex:i] integerValue];
                    
                    NSNumber *latitudeN = [[coordArray objectAtIndex:dataId] objectAtIndex:0];
                    NSNumber *longitudeN = [[coordArray objectAtIndex:dataId] objectAtIndex:1];
                    double latitude = [latitudeN floatValue];
                    double longitude = [longitudeN floatValue];
                    
                    double heading = radiansBetweenAnnotations * i;
                    
                    double coordinateLatitudeInRadians = latitude * M_PI / 180;
                    double coordinateLongitudeInRadians = longitude * M_PI / 180;
                    
                    double distanceComparedToEarth = distance / 6378100;
                    
                    double resultLatitudeInRadians = asin(sin(coordinateLatitudeInRadians) * cos(distanceComparedToEarth) + cos(coordinateLatitudeInRadians) * sin(distanceComparedToEarth) * cos(heading));
                    double resultLongitudeInRadians = coordinateLongitudeInRadians + atan2(sin(heading) * sin(distanceComparedToEarth) * cos(coordinateLatitudeInRadians), cos(distanceComparedToEarth) - sin(coordinateLatitudeInRadians) * sin(resultLatitudeInRadians));
                    
                    double newLatitude = resultLatitudeInRadians * 180 / M_PI;
                    double newLongitude = resultLongitudeInRadians * 180 / M_PI;
                    
                    latitudeN = [NSNumber numberWithFloat:newLatitude];
                    longitudeN = [NSNumber numberWithFloat:newLongitude];
                    
                    NSString *hotelName = [[coordArray objectAtIndex:dataId] objectAtIndex:2];
                    [coordArray replaceObjectAtIndex:dataId withObject:[NSArray arrayWithObjects:latitudeN, longitudeN, hotelName, nil]];
                }
            }
        }
        
        TBQuadTreeNodeData *dataArray = malloc(sizeof(TBQuadTreeNodeData) * count);
        for (NSInteger i = 0; i < count; i++) {
            TBHotelInfo* hotelInfo = malloc(sizeof(TBHotelInfo));
            
            NSString *name = [[coordArray objectAtIndex:i] objectAtIndex:2];
            hotelInfo->hotelName = malloc(sizeof(char) * name.length + 1);
            strncpy(hotelInfo->hotelName, [name UTF8String], name.length + 1);
            
            dataArray[i] = TBQuadTreeNodeDataMake([[[coordArray objectAtIndex:i] objectAtIndex:0] floatValue], [[[coordArray objectAtIndex:i] objectAtIndex:1] floatValue], hotelInfo);
        }
        
        TBBoundingBox world = TBBoundingBoxMake(19, -166, 72, -53);
        _root = TBQuadTreeBuildWithData(dataArray, count, world, 4);
    }
}

- (NSArray *)clusteredAnnotationsWithinMapRect:(MKMapRect)rect withZoomScale:(double)zoomScale
{
    double TBCellSize = TBCellSizeForZoomScale(zoomScale);
    double scaleFactor = zoomScale / TBCellSize;
    
    NSInteger minX = floor(MKMapRectGetMinX(rect) * scaleFactor);
    NSInteger maxX = floor(MKMapRectGetMaxX(rect) * scaleFactor);
    NSInteger minY = floor(MKMapRectGetMinY(rect) * scaleFactor);
    NSInteger maxY = floor(MKMapRectGetMaxY(rect) * scaleFactor);
    
    NSMutableArray *clusteredAnnotations = [[NSMutableArray alloc] init];
    for (NSInteger x = minX; x <= maxX; x++) {
        for (NSInteger y = minY; y <= maxY; y++) {
            MKMapRect mapRect = MKMapRectMake(x / scaleFactor, y / scaleFactor, 1.0 / scaleFactor, 1.0 / scaleFactor);
            
            __block double totalX = 0;
            __block double totalY = 0;
            __block int count = 0;
            
            NSMutableArray *names = [[NSMutableArray alloc] init];
            NSMutableArray *phoneNumbers = [[NSMutableArray alloc] init];
            
            TBQuadTreeGatherDataInRange(self.root, TBBoundingBoxForMapRect(mapRect), ^(TBQuadTreeNodeData data) {
                totalX += data.x;
                totalY += data.y;
                count++;
                
                TBHotelInfo hotelInfo = *(TBHotelInfo *)data.data;
                [names addObject:[NSString stringWithFormat:@"%s", hotelInfo.hotelName]];
                //[phoneNumbers addObject:[NSString stringWithFormat:@"%s", hotelInfo.hotelPhoneNumber]];
            });
            
            if (count == 1) {
                CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(totalX, totalY);
                TBClusterAnnotation *annotation = [[TBClusterAnnotation alloc] initWithCoordinate:coordinate count:count];
                annotation.title = [names lastObject];
                annotation.subtitle = [phoneNumbers lastObject];
                [clusteredAnnotations addObject:annotation];
            }
            
            if (count > 1) {
                CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(totalX / count, totalY / count);
                TBClusterAnnotation *annotation = [[TBClusterAnnotation alloc] initWithCoordinate:coordinate count:count];
                [clusteredAnnotations addObject:annotation];
            }
        }
    }
    
    
    return [NSArray arrayWithArray:clusteredAnnotations];
}

@end
