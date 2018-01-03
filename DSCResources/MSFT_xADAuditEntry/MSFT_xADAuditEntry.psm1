function Get-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [parameter(Mandatory = $true)]
        [System.String]
        $Identity,

        [parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [ValidateSet("Failure","Success")]
        [System.String[]]
        $AuditType = "Success",

        [parameter(Mandatory = $true)]
        [ValidateSet("CreateChild", "DeleteChild", "ListChildren", "Self", "ReadProperty", "WriteProperty", "DeleteTree", "ListObject", "ExtendedRight", "Delete", "ReadControl", "GenericExecute", "GenericWrite", "GenericRead", "WriteDacl", "WriteOwner", "GenericAll", "Synchronize", "AccessSystemSecurity")]
        [System.String[]]
        $Permission,

        [ValidateSet("All", "Children", "Descendents", "None", "SelfAndChildren")]
        [System.String]
        $AppliesTo = "SelfAndChilren",

        [System.String[]]
        $ExtendedPermission,

        [System.String]
        $InheritedClass,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    begin {
        Import-Module ActiveDirectory -Verbose:$false
        $RootDSE = Get-ADRootDSE

        $guidmap = @{"" = [Guid]"00000000-0000-0000-0000-000000000000"}
        Get-ADObject -SearchBase ($rootdse.SchemaNamingContext) -LDAPFilter "(schemaidguid=*)" -Properties lDAPDisplayName, schemaIDGUID | ForEach-Object {
            $guidmap[$_.lDAPDisplayName] = [System.GUID]$_.schemaIDGUID
        }


        $extendedrightsmap = @{"" = [Guid]"00000000-0000-0000-0000-000000000000"}
        Get-ADObject -SearchBase ($rootdse.ConfigurationNamingContext) -LDAPFilter "(&(objectclass=controlAccessRight)(rightsguid=*))" -Properties displayName, rightsGuid | % {
            $extendedrightsmap[$_.displayName] = [System.GUID]$_.rightsGuid
        }
    }

    process {
        Write-Verbose "Collecting permissions for path: $path"

        $IdRef = Resolve-IdentityReference -Identity $Identity

        $ACL = Get-ACL -Path "AD:\$path" -Audit

        $ACEs = $ACL.Audit | ? {
            $_.IsInherited -eq $false -and
            $_.IdentityReference -eq $IdRef.Name -and
            (Compare ($_.AuditFlags -split ', ') $AuditType | ? {$_.SideIndicator -eq "=>"}) -eq $null -and
            (Compare ($_.ActiveDirectoryRights -split ', ') $Permission | ? {$_.SideIndicator -eq "=>"}) -eq $null -and
            $_.InheritanceType -eq $AppliesTo
        }

        Write-Verbose "After basic filtering, $($ACEs.Count) ACEs have been found"

        if (($Permission -contains "Self" -or $Permission -contains "ExtendedRight") -and [string]::IsNullOrEmpty($ExtendedPermission)) {
            Throw "Self or ExtendedRight was specified but ExtendedPermission was not specified"
        }

        if ($ExtendedPermission) {
            Write-Debug "processing extendedpermission"
            $ExtendedPermission | % {
                $Perm = $_
                $ACEs = $ACEs | ? { $_.ObjectType -eq ($extendedrightsmap[$Perm]) }
            }
        }

        if ($InheritedClass) {
            Write-Debug "processing InheritedClass"
            $InheritedClassGuid = $guidmap[$InheritedClass]
            $ACEs = $ACEs | ? { $_.InheritedObjectType -eq $InheritedClassGuid }
        }

        Write-Verbose "After final filtering, $($ACEs.Count) ACEs have been found"

        if ($ACEs.Count -eq 0) {
            $Ensure = "Absent"
        }
        else {
            $Ensure = "Present"
        }

        $returnValue = @{
            Name               = $Name
            Identity           = $Identity
            Path               = $Path
            AuditType          = $AuditType
            Permission         = $ACEs.ActiveDirectoryRights | Select -Unique
            AppliesTo          = $AppliesTo
            ExtendedPermission = $ExtendedPermission
            InheritedClass     = $($GuidMap.Keys | ? {$GuidMap[$_] -eq $ACEs.InheritedObjectType; })
            Ensure             = $Ensure
        }

        $returnValue
    }
}

function Set-TargetResource {
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [parameter(Mandatory = $true)]
        [System.String]
        $Identity,

        [parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [ValidateSet("Failure","Success")]
        [System.String[]]
        $AuditType = "Success",

        [parameter(Mandatory = $true)]
        [ValidateSet("CreateChild", "DeleteChild", "ListChildren", "Self", "ReadProperty", "WriteProperty", "DeleteTree", "ListObject", "ExtendedRight", "Delete", "ReadControl", "GenericExecute", "GenericWrite", "GenericRead", "WriteDacl", "WriteOwner", "GenericAll", "Synchronize", "AccessSystemSecurity")]
        [System.String[]]
        $Permission,

        [ValidateSet("All", "Children", "Descendents", "None", "SelfAndChildren")]
        [System.String]
        $AppliesTo = "SelfAndChilren",

        [System.String[]]
        $ExtendedPermission,

        [System.String]
        $InheritedClass,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    begin {
        Import-Module ActiveDirectory -Verbose:$false
        $RootDSE = Get-ADRootDSE

        $guidmap = @{"" = [Guid]"00000000-0000-0000-0000-000000000000"}
        Get-ADObject -SearchBase ($rootdse.SchemaNamingContext) -LDAPFilter "(schemaidguid=*)" -Properties lDAPDisplayName, schemaIDGUID | % {
            $guidmap[$_.lDAPDisplayName] = [System.GUID]$_.schemaIDGUID
        }

        $extendedrightsmap = @{"" = [Guid]"00000000-0000-0000-0000-000000000000"}
        Get-ADObject -SearchBase ($rootdse.ConfigurationNamingContext) -LDAPFilter "(&(objectclass=controlAccessRight)(rightsguid=*))" -Properties displayName, rightsGuid | % {
            $extendedrightsmap[$_.displayName] = [System.GUID]$_.rightsGuid
        }
    }

    process {

        $IdRef = Resolve-IdentityReference -Identity $Identity
        $ACL = Get-Acl -Path "AD:\$path"

        if ([string]::IsNullOrWhiteSpace($ExtendedPermission) -and [string]::IsNullOrWhiteSpace($InheritedClass)) {
            $ACL.AddAuditRule((New-Object System.DirectoryServices.ActiveDirectoryAuditRule ([System.Security.Principal.SecurityIdentifier]$IdRef.SID), $Permission, $AuditType, ([System.DirectoryServices.ActiveDirectorySecurityInheritance]$AppliesTo)))
        }

        if ($ExtendedPermission -and [string]::IsNullOrWhiteSpace($InheritedClass)) {
            $ExtendedPermission | % {
                if ($Permission.Contains("ExtendedRight") -or $Permission.Contains("Self")) {
                    $eright = $extendedrightsmap[$_]
                }
                else {
                    $eright = $extendedrightsmap[""]
                }
                $ACL.AddAuditRule((New-Object System.DirectoryServices.ActiveDirectoryAuditRule ([System.Security.Principal.SecurityIdentifier]$IdRef.SID), $Permission, $AuditType, $eright, $AppliesTo, $GuidMap[""]))
            }
        }

        if ($InheritedClass -and [string]::IsNullOrWhiteSpace($ExtendedPermission)) {
            $ACL.AddAuditRule((New-Object System.DirectoryServices.ActiveDirectoryAuditRule ([System.Security.Principal.SecurityIdentifier]$IdRef.SID), $Permission, $AuditType, $extendedrightsmap[""], $AppliesTo, $GuidMap[$InheritedClass]))
        }

        if ($ExtendedPermission -and $InheritedClass) {
            $ExtendedPermission | % {
                if ($Permission.Contains("ExtendedRight") -or $Permission.Contains("Self")) {
                    $eright = $extendedrightsmap[$_]
                }
                else {
                    $eright = $extendedrightsmap[""]
                }
                $ACL.AddAuditRule((New-Object System.DirectoryServices.ActiveDirectoryAuditRule ([System.Security.Principal.SecurityIdentifier]$IdRef.SID), $Permission, $AuditType, $eright, $AppliesTo, $GuidMap[$InheritedClass]))
            }
        }

        $ACL | Set-Acl
    }
}

function Testsource {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [parameter(Mandatory = $true)]
        [System.String]
        $Identity,

        [parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [ValidateSet("Failure", "None", "Success")]
        [System.String[]]
        $AuditType = "Success",

        [parameter(Mandatory = $true)]
        [ValidateSet("CreateChild", "DeleteChild", "ListChildren", "Self", "ReadProperty", "WriteProperty", "DeleteTree", "ListObject", "ExtendedRight", "Delete", "ReadControl", "GenericExecute", "GenericWrite", "GenericRead", "WriteDacl", "WriteOwner", "GenericAll", "Synchronize", "AccessSystemSecurity")]
        [System.String[]]
        $Permission,

        [ValidateSet("All", "Children", "Descendents", "None", "SelfAndChildren")]
        [System.String]
        $AppliesTo = "All",

        [System.String[]]
        $ExtendedPermission,

        [System.String]
        $InheritedClass,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present"
    )

    (Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure
}

#region Helpers
function Resolve-IdentityReference {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Identity
    )

    process {
        try {
            Write-Verbose -Message "Resolving identity reference '$Identity'."

            if ($Identity -match '^S-\d-(\d+-){1,14}\d+$') {
                [System.Security.Principal.SecurityIdentifier]$Identity = $Identity
            }
            else {
                [System.Security.Principal.NTAccount]$Identity = $Identity
            }

            $SID = $Identity.Translate([System.Security.Principal.SecurityIdentifier])
            $NTAccount = $SID.Translate([System.Security.Principal.NTAccount])

            $OutputObject = [PSCustomObject]@{
                Name = $NTAccount.Value
                SID  = $SID.Value
            }

            return $OutputObject
        }
        catch {
            $ErrorMessage = "Could not resolve identity reference '{0}': '{1}'." -f $Identity, $_.Exception.Message
            Write-Error -Exception $_.Exception -Message $ErrorMessage
            return
        }
    }
}

#endregion


Export-ModuleMember -Function *-TargetResource

