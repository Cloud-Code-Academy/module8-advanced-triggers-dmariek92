public with sharing class OpportunityTriggerHandler extends TriggerHandler{
 
    private List<Opportunity> newOppList;
    private List<Opportunity> oldOppList;
    private Map<Id, Opportunity> newOppMap;
    private Map<Id, Opportunity> oldOppMap;
    public static Boolean hasRun = false;
    

    public OpportunityTriggerHandler(){
        this.newOppList = (List<Opportunity>)Trigger.new;
        this.oldOppList = (List<Opportunity>)Trigger.old;
        this.newOppMap = (Map<Id,Opportunity>)Trigger.newMap;
        this.oldOppMap = (Map<Id,Opportunity>)Trigger.oldMap;
    }


    public override void beforeInsert(){
        // Set default Type for new Opportunities
        for(Opportunity opp : this.newOppList){
            if (opp.Type == null){
                opp.Type = 'New Customer';
            }        
        }
    }

    /*
    * Opportunity Trigger
    * When an opportunity is updated validate that the amount is greater than 5000, and set the primary contact on the opportunity to the contact with the title of 'CEO'.
    * Trigger should only fire on update.
    */
    public override void beforeUpdate() {
       //Get contacts related to the opportunity account
       Set<Id> accountIds = new Set<Id>();
       for(Opportunity opp :  this.newOppList){
           accountIds.add(opp.AccountId);
       }
       
       Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
       Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

       for (Contact cont : contacts.values()) {
           if (!accountIdToContact.containsKey(cont.AccountId)) {
               accountIdToContact.put(cont.AccountId, cont);
           }
       }

       for(Opportunity opp : this.newOppList){
           if(opp.Amount < 5000){
               opp.addError('Opportunity amount must be greater than 5000');
           }
           if(opp.Primary_Contact__c == null){
               if (accountIdToContact.containsKey(opp.AccountId)){
                   opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
               }
           }
       }  
    }

    /*
    * Opportunity Trigger
    * When an opportunity is deleted prevent the deletion if the opportunity is closed, and notify the opportunity owner if it is deleted.
    * Trigger should only fire on delete.
    */
    public override void beforeDelete() {
        // Prevent deletion of closed Opportunities
        for (Opportunity oldOpp : this.oldOppList){
            if (oldOpp.IsClosed){
                oldOpp.addError('Cannot delete closed opportunity');
            }
        }
    }

 
    public override void afterInsert() {
        // Create a new Task for newly inserted Opportunities
        List<Task> oppTasks = new List<Task>();
        for (Opportunity opp : this.newOppList){
            Task tsk = new Task();
            tsk.Subject = 'Call Primary Contact';
            tsk.WhatId = opp.Id;
            tsk.WhoId = opp.Primary_Contact__c;
            tsk.OwnerId = opp.OwnerId;
            tsk.ActivityDate = Date.today().addDays(3);
            oppTasks.add(tsk);
        }
        insert oppTasks;
    }


    public override void afterUpdate() {
        // Append Stage changes in Opportunity Description
        List<Opportunity> updateOpps = new List<Opportunity>();
        for(Opportunity opp : this.newOppList){
            Opportunity oppOld = this.oldOppMap.get(opp.Id);
            if (oppOld.StageName != null && oppOld.StageName != opp.StageName){
                Opportunity newOpp = new Opportunity(Id = opp.Id);
                newOpp.Description += '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
                updateOpps.add(newOpp);
            }            
        }
        update updateOpps;
    }


    public override void afterDelete() {
        notifyOwnersOpportunityDeleted(this.oldOppList);
    }

    /*
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */  
    public override void afterUndelete() {    
        Set<Id> oppAccountIds = new Set<Id>(); //create set of unduplciated Opportunity AccountIds to use to query related Contacts
        for (Opportunity opp : this.newOppMap.values()){
            if (opp.AccountId != null){
                oppAccountIds.add(opp.AccountId);
            }
        }
        List<Contact> accContacts = [SELECT Id, AccountId, Name, Title FROM Contact WHERE AccountId IN :oppAccountIds AND Title = 'VP Sales'];
        Map<Id, Contact> accIdToContact = new Map<Id, Contact>(); //createa a map of AccountIds and a single related Contact that matches the critieria
        for(Contact con : accContacts){
            accIdToContact.put(con.AccountId, con);
        }
        List<Opportunity> oppsToUpdate = new List<Opportunity>(); // create a list of Opportunities to populate with updates
        for(Opportunity opp : this.newOppMap.values()){
            Id oppAccountId = opp.AccountId; // get the current Opportunity's AccountId to match to the AccountId/Contact map
            if (opp.AccountId != null && accIdToContact.containsKey(opp.AccountId) && opp.Primary_Contact__c == null){
                Opportunity newOpp = new Opportunity(Id = opp.Id);
                newOpp.Primary_Contact__c = accIdToContact.get(opp.AccountId).Id;
                oppsToUpdate.add(newOpp);
            }
        }
        update oppsToUpdate;
    }

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        // Collect owner Ids of the Opportunities being deleted
        Set<Id> oppOwnerIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppOwnerIds.add(opp.OwnerId);
        }

        // Query the Opportunity Owners to get their email addresses
        Map<Id, String> oppOwnerEmails = new Map<Id, String>();
        for (User user : [SELECT Id, Email FROM User WHERE Id IN :oppOwnerIds]) {
            oppOwnerEmails.put(user.Id, user.Email);
        }

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : opps){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { oppOwnerEmails.get(opp.OwnerId) });
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }
}