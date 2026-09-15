//
//  CContactsBridge.h
//  CContactsBridge
//
//  Created by David Sherlock on 2026.
//
//  The two Contacts APIs Swift cannot see.
//
//  `enumeratorForContactFetchRequest:` and
//  `enumeratorForChangeHistoryFetchRequest:` are both marked
//  NS_SWIFT_UNAVAILABLE("") in the SDK — not deprecated, not renamed, simply
//  not exposed, with no refined replacement. Change history is the only way to
//  ask what somebody ELSE changed in the address book, so the alternative to
//  this file is not having that at all.
//
//  Deliberately tiny: it hands back the events as an array and the token as
//  data, and every decision about what they mean stays in Swift.
//

#import <Foundation/Foundation.h>
#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads the change history, returning the events and where they end.
///
/// @param store    The store to ask.
/// @param request  What to ask for.
/// @param outToken Set to the token marking the end of the returned events,
///                 for resuming next time.
/// @param error    Set when the store refuses.
/// @return The events, or nil on failure.
NSArray *_Nullable CNKChangeHistoryEvents(CNContactStore *store,
                                          CNChangeHistoryFetchRequest *request,
                                          NSData *_Nullable *_Nullable outToken,
                                          NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
