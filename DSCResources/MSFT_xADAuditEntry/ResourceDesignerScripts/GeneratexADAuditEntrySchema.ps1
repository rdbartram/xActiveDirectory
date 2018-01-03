New-xDscResource -Name MSFT_xADAuditEntry -FriendlyName xADAuditEntry -ModuleName xActiveDirectory -Path . -Force -Property @(
    New-xDscResourceProperty -Name Name -Type string -Attribute Key -Description "A string uniquely identifiable within the configuration"
    New-xDscResourceProperty -Name Identity -Type string -Attribute Required
    New-xDscResourceProperty -Name Path -Type string -Attribute Required
    New-xDscResourceProperty -Name AuditType -Type string -Attribute Write -ValidateSet @("Failure", "None", "Success")
    New-xDscResourceProperty -Name Permission -Type string[] -Attribute Required -ValidateSet @("CreateChild", "DeleteChild", "ListChildren", "Self", "ReadProperty", "WriteProperty", "DeleteTree", "ListObject", "ExtendedRight", "Delete", "ReadControl", "GenericExecute", "GenericWrite", "GenericRead", "WriteDacl", "WriteOwner", "GenericAll", "Synchronize", "AccessSystemSecurity")
    New-xDscResourceProperty -Name AppliesTo -Type string -Attribute Write -ValidateSet @("All", "Children", "Descendents", "None", "SelfAndChildren")
    New-xDscResourceProperty -Name ExtendedPermission -Type string[] -Attribute Write
    New-xDscResourceProperty -Name InheritedClass -Type string -Attribute Write
    New-xDscResourceProperty -Name Ensure -Type string -Attribute Write -ValidateSet @("Present", "Absent")
)
