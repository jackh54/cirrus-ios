import Foundation

/// JSON shaped like the Cirrus server's responses (src/worker/jmap/*.ts in cirrus-mail).
enum Fixtures {
    static let session = """
    {
      "capabilities": {
        "urn:ietf:params:jmap:core": {"maxSizeUpload": 52428800, "maxConcurrentUpload": 4, "maxSizeRequest": 10485760,
          "maxConcurrentRequests": 4, "maxCallsInRequest": 16, "maxObjectsInGet": 500, "maxObjectsInSet": 500,
          "maxChanges": 500, "collationAlgorithms": ["i;ascii-casemap"]},
        "urn:ietf:params:jmap:mail": {}, "urn:ietf:params:jmap:submission": {},
        "urn:ietf:params:jmap:vacationresponse": {}, "urn:cirrus:params:jmap:labels": {}
      },
      "accounts": {
        "01HZPERSONAL": {"name": "me@example.com", "isPersonal": true, "isReadOnly": false,
          "accountCapabilities": {"urn:ietf:params:jmap:core": {}, "urn:ietf:params:jmap:mail": {"maxMailboxDepth": 1, "mayCreateTopLevelMailbox": true},
            "urn:ietf:params:jmap:submission": {"maxDelayedSend": 0, "submissionExtensions": {}}}},
        "01HZSHARED": {"name": "team@example.com", "isPersonal": false, "isReadOnly": false,
          "accountCapabilities": {"urn:ietf:params:jmap:core": {}, "urn:ietf:params:jmap:mail": {}}}
      },
      "primaryAccounts": {"urn:ietf:params:jmap:mail": "01HZPERSONAL", "urn:ietf:params:jmap:submission": "01HZPERSONAL"},
      "username": "me@example.com",
      "apiUrl": "https://cirrus.example.com/jmap/api",
      "downloadUrl": "https://cirrus.example.com/jmap/download/{accountId}/{blobId}/{name}?accept={type}",
      "uploadUrl": "https://cirrus.example.com/jmap/upload/{accountId}/",
      "eventSourceUrl": "https://cirrus.example.com/jmap/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
      "state": "a1b2c3d4e5f60708"
    }
    """

    static let mailboxGet = """
    {"methodResponses": [["Mailbox/get", {"accountId": "01HZPERSONAL", "state": "12", "notFound": [], "list": [
      {"id": "f_inbox", "name": "Inbox", "parentId": null, "role": "inbox", "sortOrder": 0, "totalEmails": 40, "unreadEmails": 3,
       "totalThreads": 30, "unreadThreads": 2, "isSubscribed": true, "cirrusKind": "folder", "cirrusColor": null,
       "myRights": {"mayReadItems": true, "mayAddItems": true}},
      {"id": "f_spam", "name": "Spam", "parentId": null, "role": "junk", "sortOrder": 50, "totalEmails": 1, "unreadEmails": 1,
       "totalThreads": 1, "unreadThreads": 1, "isSubscribed": true, "cirrusKind": "folder", "cirrusColor": null},
      {"id": "l_work", "name": "Work", "parentId": null, "role": null, "sortOrder": 1000, "totalEmails": 5, "unreadEmails": 0,
       "totalThreads": 4, "unreadThreads": 0, "isSubscribed": true, "cirrusKind": "label", "cirrusColor": "#2B63E8"}
    ]}, "mb"]], "sessionState": "a1b2c3d4e5f60708"}
    """

    static let threadListPage = """
    {"methodResponses": [
      ["Email/query", {"accountId": "01HZPERSONAL", "queryState": "88", "canCalculateChanges": false, "position": 0,
        "ids": ["m2", "m9"], "total": 2}, "q"],
      ["Email/get", {"accountId": "01HZPERSONAL", "state": "88", "notFound": [], "list": [
        {"id": "m2", "threadId": "t1", "mailboxIds": {"f_inbox": true, "l_work": true}, "keywords": {"$seen": true, "$flagged": true},
         "from": [{"name": "Ada", "email": "ada@example.org"}], "to": [{"name": null, "email": "me@example.com"}], "subject": "Lunch?",
         "receivedAt": "2026-11-05T09:30:00Z", "preview": "Are you free on Friday", "hasAttachment": false},
        {"id": "m9", "threadId": "t7", "mailboxIds": {"f_inbox": true}, "keywords": {},
         "from": [{"name": "", "email": "news@example.net"}], "to": null, "subject": "Weekly digest",
         "receivedAt": "2026-11-04T18:00:00.250Z", "preview": "This week", "hasAttachment": true}
      ]}, "e"],
      ["Thread/get", {"accountId": "01HZPERSONAL", "state": "5", "notFound": [], "list": [
        {"id": "t1", "emailIds": ["m1", "m2"]}, {"id": "t7", "emailIds": ["m9"]}]}, "t"]
    ], "sessionState": "a1b2c3d4e5f60708"}
    """

    static let emailDetail = """
    {"methodResponses": [["Email/get", {"accountId": "01HZPERSONAL", "state": "88", "notFound": ["gone"], "list": [
      {"id": "m2", "blobId": "m_m2", "threadId": "t1", "mailboxIds": {"f_inbox": true}, "keywords": {"$seen": true},
       "messageId": ["abc@example.org"], "inReplyTo": ["root@example.com"], "references": ["root@example.com"],
       "from": [{"name": "Ada", "email": "ada@example.org"}], "to": [{"email": "me@example.com"}], "cc": null, "bcc": null, "replyTo": null,
       "subject": "Re: Lunch?", "sentAt": "2026-11-05T09:29:58Z", "receivedAt": "2026-11-05T09:30:00Z", "hasAttachment": true,
       "preview": "Friday works", "size": 2048,
       "textBody": [{"partId": "1", "blobId": "t_m2", "size": 12, "name": null, "type": "text/plain", "charset": "utf-8", "disposition": null, "cid": null}],
       "htmlBody": [{"partId": "2", "blobId": "h_m2", "size": 30, "name": null, "type": "text/html", "charset": "utf-8", "disposition": null, "cid": null}],
       "attachments": [{"partId": "3", "blobId": "a_att1", "size": 9000, "name": "menu.pdf", "type": "application/pdf", "charset": null, "disposition": "attachment", "cid": null}],
       "bodyValues": {"1": {"value": "Friday works", "isEncodingProblem": false, "isTruncated": false},
                      "2": {"value": "<p>Friday works</p>", "isEncodingProblem": false, "isTruncated": false}}}
    ]}, "e"]], "sessionState": "x"}
    """

    static let plainTextOnly = """
    {"id": "m3", "textBody": [{"partId": "1", "type": "text/plain"}], "htmlBody": [{"partId": "1", "type": "text/plain"}],
     "bodyValues": {"1": {"value": "just text"}}}
    """

    static let emailChanges = """
    {"methodResponses": [["Email/changes", {"accountId": "01HZPERSONAL", "oldState": "88", "newState": "91", "hasMoreChanges": false,
      "created": ["m10"], "updated": ["m2"], "destroyed": ["m5"]}, "ec"]], "sessionState": "x"}
    """

    static let mailboxChanges = """
    {"methodResponses": [["Mailbox/changes", {"accountId": "01HZPERSONAL", "oldState": "12", "newState": "13", "hasMoreChanges": false,
      "created": [], "updated": ["f_inbox"], "destroyed": ["l_old"], "updatedProperties": ["totalEmails", "unreadEmails", "totalThreads", "unreadThreads"]}, "mbc"]],
      "sessionState": "x"}
    """

    static let sendResult = """
    {"methodResponses": [
      ["Email/set", {"accountId": "01HZPERSONAL", "oldState": "88", "newState": "89", "created": {"draft": {"id": "d1", "blobId": "m_d1", "threadId": "t9", "size": 321}},
        "updated": null, "destroyed": null, "notCreated": null, "notUpdated": null, "notDestroyed": null}, "draft"],
      ["EmailSubmission/set", {"accountId": "01HZPERSONAL", "oldState": "s", "newState": "s", "created": {"s1": {"id": "sub1", "threadId": "t9", "undoStatus": "final", "sendAt": "2026-11-06T10:00:00Z"}},
        "updated": null, "destroyed": null, "notCreated": null, "notUpdated": null, "notDestroyed": null}, "send"],
      ["Email/set", {"accountId": "01HZPERSONAL", "oldState": "89", "newState": "90", "created": null, "updated": {"d1": null}, "destroyed": null,
        "notCreated": null, "notUpdated": null, "notDestroyed": null}, "send"]
    ], "sessionState": "x"}
    """

    static let sendRejected = """
    {"methodResponses": [
      ["Email/set", {"accountId": "01HZPERSONAL", "oldState": "88", "newState": "89", "created": {"draft": {"id": "d1", "blobId": "m_d1", "threadId": "t9", "size": 321}}}, "draft"],
      ["EmailSubmission/set", {"accountId": "01HZPERSONAL", "oldState": "s", "newState": "s", "created": null,
        "notCreated": {"s1": {"type": "forbiddenToSend", "description": "Daily sending limit reached"}}}, "send"]
    ], "sessionState": "x"}
    """

    static let methodError = """
    {"methodResponses": [["error", {"type": "cannotCalculateChanges", "description": "State is too old"}, "ec"]], "sessionState": "x"}
    """
}
