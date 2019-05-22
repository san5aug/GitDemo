/***************************************************************************************************
*Author:Eljon Greene,
*Created Date:12/17/2018,
*Last Update:
*Version:v1,
*Description: Helper class used by WMS to retrieve all accounts a user has access to beyond accounts
*they are the owner
****************************************************************************************************/

public with sharing class AccountShareHelper {

    public static Integer getShareCount(String userId) { // need to figure out why there are multiple records
        Integer totalShareCount = 0;

        AggregateResult[] shareCountResult = [
            SELECT SUM(Count__c) TotalShares 
            FROM Account_Share_Count__c
            WHERE UserId__c = :userId
        ];

        if(shareCountResult.size() > 0) {
            totalShareCount = Integer.valueOf(shareCountResult.get(0).get('TotalShares'));
        }   

        return totalShareCount;
    }

   /*public static Integer getShareCount(String userId, List<String> accountHierachyLevel, String startId, Integer count) {
        String countQuerySOQL = ' SELECT \n' +
            '    COUNT_DISTINCT(AccountId)\n' +
            ' FROM \n' +
            '    AccountShare \n' +
            '    WHERE \n' +
            '        UserOrGroupId = \'' + userId + '\'' +
            '    AND \n' +
            '        AccountID NOT IN (\n' +
            '                            SELECT\n' + 
            '                                Id \n' +
            '                            FROM \n' +
            '                                Account\n' + 
            '                            WHERE \n' +
            '                                OwnerID = \'' + userId + '\'' + 
            '                        )\n' +
            '    AND \n' +
            '        RowCause IN (\'Team\',\'Rule\',\'Manual\') \n' +
            '    AND \n' +
            '        Account.Active_Account__c = true';

        if(accountHierachyLevel.size() > 0) {
            countQuerySOQL += ' AND Account.AccountHierarchyLevel__c IN (\'';
            countQuerySOQL += String.join(accountHierachyLevel, ',');
            countQuerySOQL += '\')';
        }

        System.debug(countQuerySOQL);

        List<SObject> shareCount = database.Query(countQuerySOQL);

        return shareCount.size();
    }*/

    public static List<AccountShare> getSharedAccounts(String userId, List<String> accountHierachyLevel, Integer limitCount) { //, String platform
       System.debug(accountHierachyLevel);
 
       return  [SELECT 
                    AccountAccessLevel, 
                    AccountId, 
                    Account.AccountNumber,  
                    Account.AccountHierarchyLevel__c, 
                    Account.Parent_Account_Number__c, 
                    Account.Platform__c, 
                    Account.Market_Segment__c,
                    CaseAccessLevel, 
                    ContactAccessLevel, 
                    OpportunityAccessLevel 
                FROM 
                    AccountShare 
                WHERE 
                    UserOrGroupId =: userId
                AND 
                    AccountID NOT IN (
                                        SELECT 
                                            Id 
                                        FROM 
                                            Account 
                                        WHERE 
                                            OwnerID =: userId
                                    ) 
                AND 
                    RowCause IN ('Team','Rule', 'Manual')
                AND 
                    Account.AccountHierarchyLevel__c IN :accountHierachyLevel
                AND 
                    Account.Active_Account__c = true
                ORDER BY 
                    Account.Market_Segment__c,
                    Account.Parent_Account_Number__c, 
                    Account.AccountNumber
                LIMIT :limitCount ]; // Internal SFDC governor limit is 50000 but SOQL limit reduced for performance reasons
                /*                AND
                    Account.Market_Segment__c =: platform

                                    
                */
    }

    public static Map<ID, AccountShareParent> getSharedAccounts(String userId, List<String> accountHierachyLevel, Boolean returnParents, Integer limitCount, Integer pageCount) {
        String shareCountQuery = '';
        String shareQuery = '';
        List<Id> allIDs = new List<ID>();  // master Account ID list for loops
        //List<ID> thisResultIDList = new List<ID>(); // temporary results list that is cleared after each iteration
        Map<ID, AccountShareParent> sharedAccounts =  new Map<ID, AccountShareParent>();  // master map of all shared accounts
        //Map<Id, Account> ownedAccounts = new Map<Id, Account>([ SELECT Id FROM Account WHERE OwnerID =: userId]);
        //Set<Id> excludeAccountIds = ownedAccounts.keySet();
        //allIDs.addAll(excludeAccountIds);
        List<String> accountIDs = new List<String>();
        String accountHierachyLevelParam = String.join(accountHierachyLevel,',').replace(',','\',\'');
        String allIDsParam = '';
        Boolean useAccountBoundaries = false;
        Integer shareCount = 0;
        Integer sizeBlock = 0;

        if(pageCount != null && pageCount > 0) {
            accountIDs = getAccountBoundaries(userId, accountHierachyLevel,pageCount);
        }

        System.debug('accountIDs:');
        System.debug(accountIDs);

        if(accountIDs.size() > 0 && accountIDs[0] != null && accountIDs[1] != null) {
            useAccountBoundaries =  true;
        }

        System.debug('pageCount:' + pageCount);

        if(pageCount == 1 || (pageCount > 1 && useAccountBoundaries)) { // only run when necessary
            shareCountQuery = 
                ' SELECT Count() \n' +
                ' FROM AccountShare \n' +
                ' WHERE UserOrGroupId = \'' + userId + '\'\n' +
                ' AND AccountId NOT IN (\n' +
                '	SELECT Id \n' +
                '   FROM Account \n' +
                '   WHERE OwnerID =\'' +  userId + '\'\n' +
                ' )\n' +
                ' AND AccountAccessLevel IN (\'Read\',\'Edit\') \n' +
                ' AND Account.AccountHierarchyLevel__c IN (\'' + accountHierachyLevelParam + '\')\n' +
                        ' AND Account.Active_Account__c = true\n' +
                        ' AND RowCause IN (\'Team\',\'Rule\',\'Manual\')\n' +
                        ' AND Account.ParentId = null\n';
            
            if(useAccountBoundaries) {
                shareCountQuery += 
                ' AND AccountId >= \'' + accountIds[0] + '\'\n' +
                ' AND AccountId <= \'' + accountIds[1] + '\'';
            }

            // First get shared accounts with no parents
            // test shareCount method
            //shareCount = getShareCount(userId, accountHierachyLevel);

            /*shareCount = SELECT Count() 
                        FROM AccountShare 
                        WHERE UserOrGroupId =: userId 
                        AND AccountId NOT IN (
                            SELECT Id 
                            FROM Account 
                            WHERE OwnerID =: userId
                        )
                        AND AccountAccessLevel IN ('Read','Edit') 
                        AND Account.AccountHierarchyLevel__c IN :accountHierachyLevel
                        AND Account.Active_Account__c = true
                        AND RowCause IN ('Team','Rule','Manual')
                        AND Account.ParentId = null
                        AND AccountId >= :accountIds[0]
                        AND AccountId <= :accountIds[1]];*/

            System.debug(shareCountQuery);

            shareCount = Database.countQuery(shareCountQuery); 
            
            System.debug(shareCount);

            sizeBlock = shareCount/2000 + (math.mod(shareCount,2000)!=0?1:0);

            // Loop over the account shares 2000 accounts at a time (2000 record limit for aggregate queries)
            for(Integer i=0;i<sizeBlock;i++){
                allIDsParam =  String.join(allIDs,',').replace(',','\',\'');

                shareQuery = 'SELECT \n' +
                            ' AccountId, \n' +
                            ' Account.AccountHierarchyLevel__c, \n' +
                            ' Account.AccountNumber \n' + 
                        ' FROM \n' + 
                        '    AccountShare \n' +
                        ' WHERE \n' +
                        '    UserOrGroupId = \'' + userId + '\'\n' +
                        ' AND AccountId NOT IN ( \n' +
                        '  	SELECT Id \n' +
                        '    FROM Account \n' +
                        '    WHERE OwnerID = \'' + userId + '\'\n' +
                        '  ) \n' +
                        ' AND \n' +
                        '    AccountAccessLevel IN (\'Read\',\'Edit\') \n' +
                        ' AND \n' +
                        '    Account.AccountHierarchyLevel__c IN (\'' + accountHierachyLevelParam + '\')\n' +
                        ' AND \n' +
                        '    RowCause IN (\'Team\',\'Rule\',\'Manual\') \n' +
                        ' AND \n' +
                        '    Account.Active_Account__c = true \n' +
                        ' AND \n' +
                        '    Account.ParentId = null \n';
                        
                if(!String.isEmpty(allIDsParam)) {
                    shareQuery += 
                        ' AND \n' +
                        ' AccountID NOT IN (\'' + allIDsParam + '\')\n';
                }

                if(useAccountBoundaries) {
                    shareQuery += 
                    ' AND AccountId >= \'' + accountIds[0] + '\'\n' +
                    ' AND AccountId <= \'' + accountIds[1] + '\'\n';
                }
                
                shareQuery +=
                    ' GROUP BY AccountId, Account.AccountHierarchyLevel__c, Account.AccountNumber LIMIT 2000'; 

                List<AggregateResult> acctShareList = Database.query(shareQuery);
                        
                for(AggregateResult thisResult: acctShareList) {
                    AccountShareParent thisSharedAcct = new AccountShareParent();
                    Id thisAccountId = (ID)thisResult.get('AccountId');

                    allIDs.add(thisAccountId);

                    //thisSharedAcct.accountHierarchyLevel = (String)thisResult.get('Account.AccountHierarchyLevel__c');
                    thisSharedAcct.accountNumber = (String)thisResult.get('AccountNumber');

                    sharedAccounts.put(thisAccountId, thisSharedAcct);
                }
            }
        }
        //sharedAccounts = getSharedAccountsNoParent(allIDs, sharedAccounts, userId, accountHierachyLevel, returnParents);
        
        // Next get shared accounts with parents

        /*shareCount = [SELECT Count()
                      FROM AccountShare
                      WHERE UserOrGroupId =: userId 
                      AND AccountId NOT IN (
                      	SELECT Id 
                        FROM Account 
                        WHERE OwnerID =: userId
                      )
                      AND Account.AccountHierarchyLevel__c IN :accountHierachyLevel
                      AND Account.Active_Account__c = true
                      AND RowCause IN ('Team','Rule','Manual')
                      AND Account.ParentId != null];*/
        
         shareCountQuery = 
            ' SELECT Count() \n' +
            ' FROM AccountShare \n' +
            ' WHERE UserOrGroupId = \'' + userId + '\'\n' +
            ' AND AccountId NOT IN (\n' +
            '	SELECT Id \n' +
            '   FROM Account \n' +
            '   WHERE OwnerID =\'' +  userId + '\'\n' +
            ' )\n' +
            ' AND AccountAccessLevel IN (\'Read\',\'Edit\') \n' +
            ' AND Account.AccountHierarchyLevel__c IN (\'' + accountHierachyLevelParam + '\')\n' +
                    ' AND Account.Active_Account__c = true\n' +
                    ' AND RowCause IN (\'Team\',\'Rule\',\'Manual\')\n' +
                    ' AND Account.ParentId != null\n';
        
        if(useAccountBoundaries) {
            shareCountQuery += 
            ' AND AccountId >= \'' + accountIds[0] + '\'\n' +
            ' AND AccountId <= \'' + accountIds[1] + '\'';
        }

        shareCount = Database.countQuery(shareCountQuery); 

        sizeBlock = shareCount/2000 + (math.mod(shareCount,2000)!=0?1:0);

        //Iterate aggregate result with blocks of 2000 to avoid exception
        for(Integer i=0;i<sizeBlock;i++){      

            allIDsParam =  String.join(allIDs,',').replace(',','\',\'');

            shareQuery = 'SELECT \n' +
                        ' AccountId, \n' +
                        ' Account.ParentId,' +
                        ' Account.AccountHierarchyLevel__c, \n' +
                        ' Account.AccountNumber, \n' + 
                        ' Account.Parent.AccountHierarchyLevel__c Parent_HierarchyLevel, \n' + 
                        ' Account.Parent.AccountNumber Parent \n' +
                    ' FROM \n' + 
                    '    AccountShare \n' +
                    ' WHERE \n' +
                    '    UserOrGroupId = \'' + userId + '\'\n' +
                    ' AND AccountId NOT IN ( \n' +
                    '  	SELECT Id \n' +
                    '    FROM Account \n' +
                    '    WHERE OwnerID = \'' + userId + '\'\n' +
                    '  ) \n' +
                    ' AND \n' +
                    '    AccountAccessLevel IN (\'Read\',\'Edit\') \n' +
                    ' AND \n' +
                    '    Account.AccountHierarchyLevel__c IN (\'' + accountHierachyLevelParam + '\')\n' +
                    ' AND \n' +
                    '    RowCause IN (\'Team\',\'Rule\',\'Manual\') \n' +
                    ' AND \n' +
                    '    Account.Active_Account__c = true \n' +
                    ' AND \n' +
                    '    Account.ParentId != null \n';
                    
            if(!String.isEmpty(allIDsParam)) {
                shareQuery +=
                    ' AND \n' +
                    ' AccountID NOT IN (\'' + allIDsParam + '\')\n';
            }

            if(useAccountBoundaries) {
                shareQuery += 
                ' AND AccountId >= \'' + accountIds[0] + '\'\n' +
                ' AND AccountId <= \'' + accountIds[1] + '\'\n';
            }
            
            shareQuery +=
                '  GROUP BY Account.ParentId, Account.AccountNumber, AccountId, Account.AccountHierarchyLevel__c, Account.Parent.AccountHierarchyLevel__c, Account.Parent.AccountNumber LIMIT 2000'; 

            System.debug(shareQuery);

            List<AggregateResult> acctShareList = Database.query(shareQuery);

            System.debug(acctShareList);
                    
            for(AggregateResult thisResult: acctShareList) {
                AccountShareParent thisSharedAcct = new AccountShareParent();
                Id thisAccountId = (ID)thisResult.get('AccountId');
                String parentHierarchy = (String)thisResult.get('Parent_HierarchyLevel');
                //thisResultIDList.add(thisAccountId);
                allIDs.add(thisAccountId);

                //thisSharedAcct.accountHierarchyLevel = (String)thisResult.get('Account.AccountHierarchyLevel__c');
                thisSharedAcct.accountNumber = (String)thisResult.get('AccountNumber');
                if(parentHierarchy == 'Grandparent') {
                    thisSharedAcct.parentAccountNumber = thisSharedAcct.accountNumber; // Supplymanager doesn't support grandparents
                } else {
                    thisSharedAcct.parentAccountNumber = (String)thisResult.get('Parent');
                }
                sharedAccounts.put(thisAccountId, thisSharedAcct);
            }  
        }
        System.debug(sharedAccounts);

        return sharedAccounts;
    }

    /*private static Map<ID, AccountShareParent> getSharedAccountsNoParent(Set<Id> allIDs,  Map<ID, AccountShareParent> sharedAccounts, String userId, List<String> accountHierachyLevel, Boolean returnParents) {
        // First get shared accounts with no parents
        List<AggregateResult> totalShareCountList = new List<AggregateResult>();
        Integer shareCount = 0;

        shareCount = [SELECT COUNT()
                      FROM AccountShare 
                      WHERE UserOrGroupId =: userId 
                      AND AccountId NOT IN (
                      	SELECT Id 
                        FROM Account 
                        WHERE OwnerID =: userId
                      )
                      AND Account.AccountHierarchyLevel__c IN :accountHierachyLevel
                      AND Account.Active_Account__c = true
                      AND RowCause IN ('Team','Rule','Manual')
                      AND Account.ParentId = null];

        Integer sizeBlock = shareCount/2000 + (math.mod(shareCount,2000)!=0?1:0);

        // Loop over the account shares 2000 accounts at a time (2000 record limit for aggregate queries)
        for(Integer i=0;i<sizeBlock;i++){ 
            for(List<AggregateResult> acctShareList : [
                    SELECT 
                        AccountId,
                        Account.AccountHierarchyLevel__c,
                        Account.AccountNumber
                    FROM 
                        AccountShare 
                    WHERE 
                        UserOrGroupId =: userId 
                    AND 
                        AccountID NOT IN :allIDs
                    AND 
                        Account.AccountHierarchyLevel__c IN :accountHierachyLevel
                    AND 
                        RowCause IN ('Team','Rule','Manual')
                    AND 
                        Account.Active_Account__c = true
                    AND 
                        Account.ParentId = null
                    GROUP BY AccountId, Account.AccountHierarchyLevel__c, Account.AccountNumber LIMIT 2000]) { 
                        System.debug(acctShareList);
                     
                        for(AggregateResult thisResult: acctShareList) {
                            AccountShareParent thisSharedAcct = new AccountShareParent();
                            Id thisAccountId = (ID)thisResult.get('AccountId');

                            allIDs.add(thisAccountId);

                            //thisSharedAcct.accountHierarchyLevel = (String)thisResult.get('Account.AccountHierarchyLevel__c');
                            thisSharedAcct.accountNumber = (String)thisResult.get('AccountNumber');

                            sharedAccounts.put(thisAccountId, thisSharedAcct);
                        }
            }
        }

        return sharedAccounts;
    }*/


    public static List<String> getAccountBoundaries(String userId, List<String> hierarchyLevel, Integer pageNumber) {
        List<String> accountIds = new String[2];

        // get account share pages and get account Ids for search boundaries
        List<Account_Share_Page__c> sharePageList = [
                SELECT Account__c 
                FROM Account_Share_Page__c 
                WHERE Hierarchy_Level__c  IN :hierarchyLevel
                AND ShareUser__c =: userId
                ORDER BY Account__c
        ];

        System.debug(sharePageList);

        if(sharePageList.size() > 0 && pageNumber != null) {
            if(pageNumber == 1) { // only set the last Account Id in the page
                accountIds[0] = '';
                accountIds[1] = String.valueOf(sharePageList.get(0).Account__c);
            } else if(sharePageList.size() == 1 && pageNumber == 2) {
                accountIds[0] = String.valueOf(sharePageList.get(0).Account__c);
                accountIds[1] = '';
            } else if(pageNumber == sharePageList.size()) {
                accountIds[0] = String.valueOf(sharePageList.get(pageNumber-1).Account__c);
                accountIds[1] = '';
            } else {
                System.debug('inside condition');
                try {
                    accountIds[0] = String.valueOf(sharePageList.get(pageNumber-2).Account__c);
                    System.debug('sharePageList.get(pageNumber-2).Account__c=' + sharePageList.get(pageNumber-2).Account__c);
                } catch (Exception e) {

                }
                try {
                    accountIds[1] = String.valueOf(sharePageList.get(pageNumber-1).Account__c);
                    System.debug('sharePageList.get(pageNumber-1).Account__c=' + sharePageList.get(pageNumber-1).Account__c);
                } catch (Exception e) {

                }
            }
            
        }
        System.debug(accountIds);

        return accountIds;
    }
    public class AccountShareParent {
        //public String accountHierarchyLevel;
        public String accountNumber;
        public String parentAccountNumber;
    }
}