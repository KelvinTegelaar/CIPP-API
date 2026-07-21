function New-CIPPTeam {
    <#
    .SYNOPSIS
    Create a new Microsoft Team and return its group id and SharePoint site URL

    .DESCRIPTION
    Creates a Team via the Graph Teams API (standard template) so the full Teams stack
    (group, channels, Teams-enabled SharePoint site) is provisioned, then waits for the
    backing SharePoint site to become available and returns both identifiers.

    .PARAMETER DisplayName
    The display name of the team

    .PARAMETER Description
    The description of the team

    .PARAMETER Owner
    UPN of the team owner. Required by Graph when creating a team with application permissions.

    .PARAMETER Visibility
    Public or Private. Defaults to Private.

    .PARAMETER TenantFilter
    The tenant to create the team in
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [string]$Description = '',

        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [ValidateSet('Public', 'Private')]
        [string]$Visibility = 'Private',

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Create Team',
        $Headers
    )

    $TeamsSettings = [PSCustomObject]@{
        'template@odata.bind' = "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
        'visibility'          = $Visibility.ToLower()
        'displayName'         = $DisplayName
        'description'         = $Description
        'members'             = @(
            @{
                '@odata.type'     = '#microsoft.graph.aadUserConversationMember'
                'roles'           = @('owner')
                'user@odata.bind' = "https://graph.microsoft.com/beta/users('$Owner')"
            }
        )
    } | ConvertTo-Json -Depth 10

    if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Create new Team')) { return }

    try {
        # Team creation is async: Graph returns 202 with a Content-Location of /teams('{id}').
        $ResponseHeaders = New-GraphPostRequest -AsApp $true -uri 'https://graph.microsoft.com/beta/teams' -tenantid $TenantFilter -type POST -body $TeamsSettings -returnHeaders $true
        $ContentLocation = [string]($ResponseHeaders.'Content-Location' | Select-Object -First 1)
        $GroupId = [regex]::Match($ContentLocation, "teams\('([^']+)'\)").Groups[1].Value
        if (-not $GroupId) {
            throw "Team creation was accepted but no team id was returned (Content-Location: '$ContentLocation')."
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Team $DisplayName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }

    # Wait for the backing SharePoint site to be provisioned so the caller can add libraries.
    $SiteUrl = $null
    $Attempts = 0
    do {
        $Attempts++
        try {
            $Site = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/sites/root?`$select=id,webUrl" -tenantid $TenantFilter -AsApp $true
            $SiteUrl = $Site.webUrl
        } catch {
            if ($Attempts -lt 10) { Start-Sleep -Seconds 6 }
        }
    } while (-not $SiteUrl -and $Attempts -lt 10)

    if (-not $SiteUrl) {
        $Result = "Created Team $DisplayName ($GroupId) but the SharePoint site was not available yet. Libraries and permissions were not applied."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Warning
        throw $Result
    }

    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Team $DisplayName with site $SiteUrl" -sev Info
    return [PSCustomObject]@{
        GroupId = $GroupId
        SiteUrl = $SiteUrl
    }
}
