public with sharing class ResourcesAndAvailabilityController {

    public ResourcesAndAvailabilityController() {
    }

    @RemoteAction
    public static Map<String, Object> getData(String input) {
        Map<Id, User> availableUsers = new Map<Id, User>(
            [SELECT Id FROM User WHERE isActive = true]
        );

        Map<Id, List<PHG_Employee_Availability__c>> availMapWithUserId = new Map<Id, List<PHG_Employee_Availability__c>>();
        for (PHG_Employee_Availability__c availItem : [SELECT Id, Name, Date_From__c, Date_To__c, Hours__c, OwnerId
                                                       FROM PHG_Employee_Availability__c
                                                       WHERE OwnerId IN :availableUsers.keySet()
                                                           AND Date_To__c >= TODAY
                                                       ORDER BY CreatedDate ASC]) {

            if (availMapWithUserId.containsKey(availItem.OwnerId)) {
                availMapWithUserId.get(availItem.OwnerId).add(availItem);
            } else {
                availMapWithUserId.put(
                    availItem.OwnerId,
                    new List<PHG_Employee_Availability__c>{
                        availItem
                    }
                );
            }
        }

        Map<Id, List<Request__c>> vacationMapWithUserId = new Map<Id, List<Request__c>>();
        for (Request__c requestItem : [SELECT Id, Employee__c, Vacation_Start__c, Vacation_End__c, Is_Approved__c
                                       FROM Request__c
                                       WHERE Employee__c IN :availableUsers.keySet()
                                           AND RecordType.DeveloperName = 'Vacation'
                                       ORDER BY Vacation_Start__c ASC]) {

            if (vacationMapWithUserId.containsKey(requestItem.Employee__c)) {
                vacationMapWithUserId.get(requestItem.Employee__c).add(requestItem);
            } else {
                vacationMapWithUserId.put(
                    requestItem.Employee__c,
                    new List<Request__c>{
                        requestItem
                    }
                );
            }
        }

        String contactQuery = '' +
            'SELECT Id, Name, Experience_Level__c, English_Level__c, Employee_User__c, Job_Title__c, ' +
            'Email, Phone, Skype__c, Google_Talk__c, Birthdate, Hired_Date__c, Emergency_Phone__c, ' +
            'Employee_User__r.Manager.Name, Account.Name, ' +
            '(SELECT Id, Name, Project__r.Id, Project__r.Name, Project__r.Customer__c, Start_Date__c, ' +
            'End_Date__c FROM Resource_Projects__r ), ' +
            '(SELECT Id, Skill__r.Name, Score__c FROM Employees__r WHERE Is_Current__c = TRUE), ' +
            '(SELECT Id, Name, Certificate__r.Name, Certificate__r.Icon_Id__c FROM Employee_Certifications__r), ' +
            '(SELECT Id, Visa_Expiration_Date__c, Visa_Country__c, Visa_Image__c FROM Employee_Private_Documents__r ' +
            'WHERE Visa_Image__c = \'visa_usa\') ' +
            'FROM Contact WHERE Employee_User__c IN :userIds AND RecordType.DeveloperName = \'Employee\' ' +
            'AND Employee_Status__c = \'Hired\' ORDER BY Name ASC LIMIT 10000';
        List<Contact> allContactsByUsers = HelperWithoutSharing.getUserRelatedContacts(
            contactQuery,
            availableUsers.keySet()
        );

        List<ContactWrapper> contactWrappers = new List<ContactWrapper>();
        List<String> listOfAccounts = new List<String>();
        List<String> listOfDepartments = new List<String>();
        for (Contact contactItem : allContactsByUsers) {
            ContactWrapper newContactWrapper = new ContactWrapper(
                contactItem,
                availMapWithUserId.get(contactItem.Employee_User__c),
                vacationMapWithUserId.get(contactItem.Employee_User__c)
            );
            contactWrappers.add(newContactWrapper);
            if (!String.isBlank(contactItem.Account.Id)) {
                listOfAccounts.add(contactItem.Account.Name);
            }
            if (!String.isBlank(contactItem.Job_Title__c)) {
                listOfDepartments.add(contactItem.Job_Title__c);
            }
        }
        listOfAccounts = new List<String>(new Set<String>(listOfAccounts));
        listOfDepartments = new List<String>(new Set<String>(listOfDepartments));
        listOfAccounts.sort();
        listOfDepartments.sort();

        Map<String, Object> outData = new Map<String, Object>();
        outData.put('ContactsWrap', contactWrappers);
        outData.put('Accounts', listOfAccounts);
        outData.put('Departments', listOfDepartments);
        outData.put('Projects', getProjects());
        outData.put('Clients', getClients());

        return outData;
    }

    private static List<Object> getProjects() {
        List<Object> listOfProjects = new List<Object>{
            new Map<String, String>{
                'Name' => 'All projects'
            }
        };
        for (NEW_Project__c projectItem : [SELECT Id, Name, Customer__c
                                           FROM NEW_Project__c
                                           ORDER BY Name ASC]) {

            listOfProjects.add(projectItem);
        }
        return listOfProjects;
    }

    private static List<Object> getClients() {
        List<Object> listOfClients = new List<Object>{
            new Map<String, Object>{
                'Account__r' => new Map<String, String>{'Name' => 'All clients'}
            }
        };
        for (NEW_Client__c clientsItem : [SELECT Id, Account__r.Name
                                          FROM NEW_Client__c
                                          ORDER BY Account__r.Name ASC]) {

            listOfClients.add(clientsItem);
        }
        return listOfClients;
    }

    public class ContactWrapper {
        private Contact contact;
        private Integer availabilityHours;
        private String availabilityAddInfo;
        private String lastVacation;
        private String nextVacation;
        private NEW_Project_Resource__c currentProject;

        public ContactWrapper(Contact contactIn, List<PHG_Employee_Availability__c> emplAvails, List<Request__c> emplRequest) {
            this.contact = contactIn;
            this.availabilityHours = (emplAvails != null) ? emplAvails[0].Hours__c.intValue() : 8;
            this.availabilityAddInfo = (emplAvails != null) ? getAvailAddInfo(emplAvails) : '';
            this.lastVacation = (emplRequest != null) ? getLastVacation(emplRequest) : '';
            this.nextVacation = (emplRequest != null) ? getNextVacation(emplRequest) : '';
            this.currentProject = getCurrentProject(contactIn.Resource_Projects__r);
        }

        private String getAvailAddInfo(List<PHG_Employee_Availability__c> emplAvails) {
            if (emplAvails[0].Hours__c < 8 && emplAvails.size() == 1) {
                return (' (Available from ' + (emplAvails[0].Date_To__c.addDays(1)).format() + ')');
            } else if (emplAvails[0].Hours__c < 8 && emplAvails.size() >= 1 && emplAvails[1].Hours__c > 0) {
                return (' (Available ' + emplAvails[1].Hours__c.intValue() + 'h ' +
                    'from ' + (emplAvails[0].Date_To__c.addDays(1)).format() + ')');
            } else if (emplAvails[0].Hours__c == 8 && emplAvails.size() >= 1) {
                return (' (Available until ' + emplAvails[1].Date_From__c.format() + ')');
            }
            return '';
        }

        private String getLastVacation(List<Request__c> requests) {
            Request__c lastRequest = null;
            System.debug(requests);
            for (Request__c requestItem : requests) {
                if (requestItem.Vacation_Start__c > Date.today()) {
                    break;
                } else {
                    lastRequest = requestItem;
                }
            }
            if (lastRequest != null) {
                Integer monthCount = lastRequest.Vacation_End__c.monthsBetween(Date.today());
                if (monthCount < 0) {
                    return 'Last vacation ends next month.';
                } else if (monthCount == 0) {
                    return 'Last vacation in current month.';
                } else if (monthCount == 1) {
                    return 'Last vacation was ' + monthCount + ' month ago.';
                } else {
                    return 'Last vacation was ' + monthCount + ' months ago.';
                }
            }
            return '';
        }

        private String getNextVacation(List<Request__c> requests) {
            Request__c nextRequest = null;
            for (Request__c requestItem : requests) {
                if (requestItem.Vacation_Start__c > Date.today()) {
                    nextRequest = requestItem;
                    break;
                }
            }
            if (nextRequest != null) {
                Integer monthCount = Date.today().monthsBetween(nextRequest.Vacation_Start__c);
                if (monthCount == 0) {
                    return 'Next vacation is in current month.';
                } else if (monthCount == 1) {
                    return 'Next vacation is in next month.';
                } else {
                    return 'Next vacation is in ' + monthCount + ' months.';
                }
            }
            return '';
        }

        private NEW_Project_Resource__c getCurrentProject(List<NEW_Project_Resource__c> projects) {
            for (NEW_Project_Resource__c projResItem : projects) {
                if (projResItem.Start_Date__c <= Date.today() && projResItem.End_Date__c >= Date.today()) {
                    return projResItem;
                }
            }
            return null;
        }

    }

}