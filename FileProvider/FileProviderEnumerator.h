//
//  FileProviderEnumerator.h
//  FileProvider
//
//  Created by Alfred Neumayer on 17.06.21.
//

#import <FileProvider/FileProvider.h>
#include "SharedStateOverview.h"

@interface FileProviderEnumerator : NSObject<NSFileProviderEnumerator>
{
    NSFileProviderItemIdentifier itemIdentifier;
    NSInteger currentAnchor;
}
- (instancetype) initWithItemIdentifier: (NSFileProviderItemIdentifier)containerItemIdentifier withAnchor:(NSInteger)currentAnchor;
@end
