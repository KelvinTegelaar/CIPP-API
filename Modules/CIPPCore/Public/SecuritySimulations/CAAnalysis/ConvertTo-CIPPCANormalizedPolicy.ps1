function ConvertTo-CIPPCANormalizedPolicy {
    <#
    .SYNOPSIS
        Normalizes a cached conditionalAccessPolicy so every collection the gap analysis reads is present.
    .DESCRIPTION
        The beta Graph shape leaves many collections null.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy
    )

    $AsStrings = {
        param($Value)
        , [string[]]@(@($Value) | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
    }

    $Conditions = $Policy.conditions
    $Users = $Conditions.users
    $Apps = $Conditions.applications

    $Platforms = $null
    if ($null -ne $Conditions.platforms) {
        $Platforms = [PSCustomObject]@{
            includePlatforms = & $AsStrings $Conditions.platforms.includePlatforms
            excludePlatforms = & $AsStrings $Conditions.platforms.excludePlatforms
        }
    }

    $Locations = $null
    if ($null -ne $Conditions.locations) {
        $Locations = [PSCustomObject]@{
            includeLocations = & $AsStrings $Conditions.locations.includeLocations
            excludeLocations = & $AsStrings $Conditions.locations.excludeLocations
        }
    }

    $Grant = $Policy.grantControls
    $Operator = $null
    if ($null -ne $Grant) {
        $Operator = if ($Grant.operator) { "$($Grant.operator)" } else { 'OR' }
    }
    $GrantControls = [PSCustomObject]@{
        present                     = ($null -ne $Grant)
        operator                    = $Operator
        builtInControls             = & $AsStrings $Grant.builtInControls
        customAuthenticationFactors = & $AsStrings $Grant.customAuthenticationFactors
        termsOfUse                  = & $AsStrings $Grant.termsOfUse
        authenticationStrength      = $Grant.authenticationStrength
    }

    [PSCustomObject]@{
        id               = "$($Policy.id)"
        displayName      = if ($Policy.displayName) { "$($Policy.displayName)" } else { "$($Policy.id)" }
        state            = if ($Policy.state) { "$($Policy.state)" } else { 'disabled' }
        templateId       = $Policy.templateId
        createdDateTime  = $Policy.createdDateTime
        modifiedDateTime = $Policy.modifiedDateTime
        conditions       = [PSCustomObject]@{
            users                      = [PSCustomObject]@{
                includeUsers                 = & $AsStrings $Users.includeUsers
                excludeUsers                 = & $AsStrings $Users.excludeUsers
                includeGroups                = & $AsStrings $Users.includeGroups
                excludeGroups                = & $AsStrings $Users.excludeGroups
                includeRoles                 = & $AsStrings $Users.includeRoles
                excludeRoles                 = & $AsStrings $Users.excludeRoles
                includeGuestsOrExternalUsers = $Users.includeGuestsOrExternalUsers
                excludeGuestsOrExternalUsers = $Users.excludeGuestsOrExternalUsers
            }
            applications               = [PSCustomObject]@{
                includeApplications                         = & $AsStrings $Apps.includeApplications
                excludeApplications                         = & $AsStrings $Apps.excludeApplications
                includeUserActions                          = & $AsStrings $Apps.includeUserActions
                includeAuthenticationContextClassReferences = & $AsStrings $Apps.includeAuthenticationContextClassReferences
                applicationFilter                           = $Apps.applicationFilter
            }
            clientAppTypes             = & $AsStrings $Conditions.clientAppTypes
            platforms                  = $Platforms
            locations                  = $Locations
            userRiskLevels             = & $AsStrings $Conditions.userRiskLevels
            signInRiskLevels           = & $AsStrings $Conditions.signInRiskLevels
            servicePrincipalRiskLevels = & $AsStrings $Conditions.servicePrincipalRiskLevels
            devices                    = $Conditions.devices
            clientApplications         = $Conditions.clientApplications
            agentIdRiskLevels          = $Conditions.agentIdRiskLevels
            insiderRiskLevels          = $Conditions.insiderRiskLevels
            authenticationFlows        = $Conditions.authenticationFlows
        }
        grantControls    = $GrantControls
        sessionControls  = $Policy.sessionControls
    }
}
