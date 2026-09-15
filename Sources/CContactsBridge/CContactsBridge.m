//
//  CContactsBridge.m
//  CContactsBridge
//
//  Created by David Sherlock on 2026.
//

#import "include/CContactsBridge.h"

NSArray *_Nullable CNKChangeHistoryEvents(CNContactStore *store,
                                          CNChangeHistoryFetchRequest *request,
                                          NSData *_Nullable *_Nullable outToken,
                                          NSError *_Nullable *_Nullable error) {
    CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *result =
        [store enumeratorForChangeHistoryFetchRequest:request error:error];
    if (result == nil) { return nil; }

    // Drained here rather than handed back as an enumerator: NSEnumerator is
    // lazy over a live cursor, and a Swift caller iterating it after this
    // function returns would be reading a result whose owner has gone.
    NSMutableArray *events = [NSMutableArray array];
    for (CNChangeHistoryEvent *event in result.value) {
        [events addObject:event];
    }
    if (outToken != NULL) { *outToken = result.currentHistoryToken; }
    return events;
}
