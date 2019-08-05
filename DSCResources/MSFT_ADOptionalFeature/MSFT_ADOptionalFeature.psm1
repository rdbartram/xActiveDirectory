$script:resourceModulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:modulesFolderPath = Join-Path -Path $script:resourceModulePath -ChildPath 'Modules'

$script:localizationModulePath = Join-Path -Path $script:modulesFolderPath -ChildPath 'ActiveDirectoryDsc.Common'
Import-Module -Name (Join-Path -Path $script:localizationModulePath -ChildPath 'ActiveDirectoryDsc.Common.psm1')

$script:localizedData = Get-LocalizedData -ResourceName 'MSFT_ADOptionalFeature'

<#
    .SYNOPSIS
        Gets the state of the Active Directory Optional Feature.

    .PARAMETER FeatureName
        The name of the Optional feature to be enabled.

    .PARAMETER ForestFQDN
        The fully qualified domain name (FQDN) of the forest in which to change the Optional feature.

    .PARAMETER EnterpriseAdministratorCredential
        The user account credentials to use to perform this task.

#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $FeatureName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ForestFQDN,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $EnterpriseAdministratorCredential
    )

    $previousErrorActionPreference = $ErrorActionPreference

    try
    {
        # AD cmdlets generate non-terminating errors.
        $ErrorActionPreference = 'Stop'

        $Feature = Get-ADOptionalFeature -Filter {name -eq $FeatureName} -Server $ForestFQDN -Credential $EnterpriseAdministratorCredential

        if ($Feature.EnabledScopes.Count -gt 0)
        {
            Write-Verbose -Message ($script:localizedData.OptionalFeatureEnabled -f $FeatureName)
            $FeatureEnabled = $True
        }
        else
        {
            Write-Verbose -Message ($script:localizedData.OptionalFeatureNotEnabled -f $FeatureName)
            $FeatureEnabled = $False
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException], [Microsoft.ActiveDirectory.Management.ADServerDownException]
    {
        $errorMessage = $script:localizedData.ForestNotFound -f $ForestFQDN
        New-ObjectNotFoundException -Message $errorMessage -ErrorRecord $_
    }
    catch [System.Security.Authentication.AuthenticationException]
    {
        $errorMessage = $script:localizedData.CredentialError
        New-InvalidArgumentException -Message $errorMessage -ArgumentName 'EnterpriseAdministratorCredential'
    }
    catch
    {
        $errorMessage = $script:localizedData.GetUnhandledException -f $ForestFQDN
        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return @{
        ForestFQDN = $ForestFQDN
        FeatureName = $FeatureName
        Enabled = $FeatureEnabled
    }
}

<#
    .SYNOPSIS
        Sets the state of the Active Directory Optional Feature.

    .PARAMETER FeatureName
        The name of the Optional feature to be enabled.

    .PARAMETER ForestFQDN
        The fully qualified domain name (FQDN) of the forest in which to change the Optional feature.

    .PARAMETER EnterpriseAdministratorCredential
        The user account credentials to use to perform this task.

#>
function Set-TargetResource
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $FeatureName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ForestFQDN,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $EnterpriseAdministratorCredential
    )

    $previousErrorActionPreference = $ErrorActionPreference

    try
    {
        # AD cmdlets generate non-terminating errors.
        $ErrorActionPreference = 'Stop'

        $feature = Get-ADOptionalFeature -Filter {name -eq $FeatureName} -Server $ForestFQDN -Credential $EnterpriseAdministratorCredential

        $forest = Get-ADForest -Server $ForestFQDN -Credential $EnterpriseAdministratorCredential
        $domain = Get-ADDomain -Server $ForestFQDN -Credential $EnterpriseAdministratorCredential


        # Check minimum forest level and throw if not
        if (($forest.ForestMode -as [int]) -lt ($feature.RequiredForestMode -as [int]))
        {
            throw ($script:localizedData.ForestFunctionalLevelError -f $forest.ForestMode)
        }

        # Check minimum domain level and throw if not
        if (($domain.DomainMode -as [int]) -lt ($feature.RequiredDomainMode -as [int]))
        {
            throw ($script:localizedData.DomainFunctionalLevelError -f $domain.DomainMode)
        }

        Write-Verbose -Message ($script:localizedData.EnablingOptionalFeature -f $forest.RootDomain, $FeatureName)

        Enable-ADOptionalFeature -Identity $FeatureName -Scope ForestOrConfigurationSet `
            -Target $forest.RootDomain -Server $forest.DomainNamingMaster `
            -Credential $EnterpriseAdministratorCredential `
            -Verbose
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException], [Microsoft.ActiveDirectory.Management.ADServerDownException]
    {
        $errorMessage = $script:localizedData.ForestNotFound -f $ForestFQDN
        New-ObjectNotFoundException -Message $errorMessage -ErrorRecord $_
    }
    catch [System.Security.Authentication.AuthenticationException]
    {
        $errorMessage = $script:localizedData.CredentialError
        New-InvalidArgumentException -Message $errorMessage -ArgumentName 'EnterpriseAdministratorCredential'
    }
    catch
    {
        $errorMessage = $script:localizedData.SetUnhandledException -f $ForestFQDN
        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

<#
    .SYNOPSIS
        Tests the state of the Active Directory Optional Feature.

    .PARAMETER FeatureName
        The name of the Optional feature to be enabled.

    .PARAMETER ForestFQDN
        The fully qualified domain name (FQDN) of the forest in which to change the Optional feature.

    .PARAMETER EnterpriseAdministratorCredential
        The user account credentials to use to perform this task.

#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $FeatureName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ForestFQDN,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $EnterpriseAdministratorCredential
    )

    $previousErrorActionPreference = $ErrorActionPreference

    try
    {
        # AD cmdlets generate non-terminating errors.
        $ErrorActionPreference = 'Stop'

        $State = Get-TargetResource @PSBoundParameters

        if ($true -eq $State.Enabled)
        {
            Write-Verbose -Message ($script:localizedData.OptionalFeatureEnabled -f $FeatureName)
            Return $True
        }
        else
        {
            Write-Verbose -Message ($script:localizedData.OptionalFeatureNotEnabled -f $FeatureName)
            Return $False
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException], [Microsoft.ActiveDirectory.Management.ADServerDownException]
    {
        $errorMessage = $script:localizedData.ForestNotFound -f $ForestFQDN
        New-ObjectNotFoundException -Message $errorMessage -ErrorRecord $_
    }
    catch [System.Security.Authentication.AuthenticationException]
    {
        $errorMessage = $script:localizedData.CredentialError
        New-InvalidArgumentException -Message $errorMessage -ArgumentName 'EnterpriseAdministratorCredential'
    }
    catch
    {
        $errorMessage = $script:localizedData.TestUnhandledException -f $ForestFQDN
        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

Export-ModuleMember -Function *-TargetResource