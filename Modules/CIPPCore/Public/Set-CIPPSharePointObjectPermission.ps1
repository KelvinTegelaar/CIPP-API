function Set-CIPPSharePointObjectPermission {
    <#
    .SYNOPSIS
    Grant a SharePoint permission level on a site root web or a document library

    .DESCRIPTION
    Grants groups a SharePoint permission level (Read, Contribute, Edit, Design or Full
    Control) on either the root web of a site or on a specific list/library. Groups are
    referenced by display name (the same convention Conditional Access templates use) and
    resolved against the target tenant at apply time, so templates stay tenant-agnostic.

    .PARAMETER SiteUrl
    The full URL of the site

    .PARAMETER ListId
    Optional list/library id. When omitted the permission is applied to the root web.

    .PARAMETER PermissionLevel
    read, contribute, edit, design or fullControl

    .PARAMETER GroupNames
    One or more group display names to grant the permission to

    .PARAMETER CreateMissingGroups
    Create a security group for any display name that does not resolve in the target tenant

    .PARAMETER TenantFilter
    The tenant the site belongs to
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [string]$ListId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('read', 'contribute', 'edit', 'design', 'fullControl')]
        [string]$PermissionLevel,

        [Parameter(Mandatory = $true)]
        [string[]]$GroupNames,

        [switch]$CreateMissingGroups,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Set SharePoint Permission',
        $Headers
    )

    # Standard SharePoint role definition IDs.
    $RoleDefinitionIds = @{
        'read'        = 1073741826
        'contribute'  = 1073741827
        'design'      = 1073741828
        'fullControl' = 1073741829
        'edit'        = 1073741830
    }
    $RoleDefId = $RoleDefinitionIds[$PermissionLevel]

    # Resolve group display names against the target tenant, CA-template style.
    $AllGroups = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/groups?$select=id,displayName,groupTypes&$top=999' -tenantid $TenantFilter -AsApp $true

    $Principals = [System.Collections.Generic.List[object]]::new()
    $NotFound = [System.Collections.Generic.List[string]]::new()
    foreach ($GroupName in $GroupNames) {
        if ([string]::IsNullOrWhiteSpace($GroupName)) { continue }
        $MatchedGroup = @($AllGroups | Where-Object -Property displayName -EQ $GroupName) | Select-Object -First 1
        $NewlyCreated = $false
        if (-not $MatchedGroup -and $CreateMissingGroups.IsPresent) {
            # Create a security group carrying the requested display name.
            try {
                $MailNickname = ($GroupName -replace '[^A-Za-z0-9]', '').ToLower()
                if (-not $MailNickname) { $MailNickname = "cippgroup$((New-Guid).Guid.Substring(0,8))" }
                $GroupBody = ConvertTo-Json -Compress -InputObject @{
                    displayName     = $GroupName
                    mailEnabled     = $false
                    mailNickname    = $MailNickname
                    securityEnabled = $true
                    description     = 'Created by CIPP during SharePoint template deployment'
                }
                $MatchedGroup = New-GraphPostRequest -AsApp $true -uri 'https://graph.microsoft.com/v1.0/groups' -tenantid $TenantFilter -type POST -body $GroupBody
                $NewlyCreated = $true
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Created security group $GroupName because it did not exist." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to create security group $GroupName. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $NotFound.Add("$GroupName (creation failed)")
                continue
            }
        }
        if (-not $MatchedGroup) {
            $NotFound.Add($GroupName)
            continue
        }
        # Microsoft 365 groups use the federated directory claim; security groups the tenant claim.
        $LogonName = if (@($MatchedGroup.groupTypes) -contains 'Unified') {
            "c:0o.c|federateddirectoryclaimprovider|$($MatchedGroup.id)"
        } else {
            "c:0t.c|tenant|$($MatchedGroup.id)"
        }
        $Principals.Add([PSCustomObject]@{
                LogonName    = $LogonName
                Label        = $GroupName
                NewlyCreated = $NewlyCreated
            })
    }

    if ($Principals.Count -eq 0) {
        throw "None of the groups ($($GroupNames -join ', ')) could be found in $TenantFilter by display name."
    }

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"
    $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
    $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"
    $TargetLabel = if ($ListId) { "library $ListId" } else { 'site root' }

    if (-not $PSCmdlet.ShouldProcess($SiteUrl, "Grant $PermissionLevel on $TargetLabel")) { return }

    # Libraries inherit from the web by default: break inheritance (copying assignments) first.
    if ($ListId) {
        $ListInfo = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$ListId')?`$select=HasUniqueRoleAssignments" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
        if (-not $ListInfo.HasUniqueRoleAssignments) {
            $null = New-GraphPostRequest -uri "$BaseUri/web/lists(guid'$ListId')/breakroleinheritance(copyRoleAssignments=true,clearSubscopes=false)" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
        }
        $AssignmentUri = "$BaseUri/web/lists(guid'$ListId')/roleassignments"
    } else {
        $AssignmentUri = "$BaseUri/web/roleassignments"
    }

    $Granted = [System.Collections.Generic.List[string]]::new()
    $Failed = [System.Collections.Generic.List[string]]::new()
    foreach ($Principal in $Principals) {
        try {
            $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = $Principal.LogonName }

            # Newly created groups take a while to replicate from Entra to SharePoint, so
            # ensureuser initially fails with 'could not be found'. Retry with backoff:
            # generously for groups created moments ago, briefly for pre-existing ones.
            $MaxAttempts = $Principal.NewlyCreated ? 8 : 2
            $EnsuredUser = $null
            for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
                try {
                    $EnsuredUser = New-GraphPostRequest -uri "$BaseUri/web/ensureuser" -tenantid $TenantFilter -scope $Scope -type POST -body $EnsureBody -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                    break
                } catch {
                    $IsNotFound = $_.Exception.Message -match 'could not be found|-2146232832'
                    if ($IsNotFound -and $Attempt -lt $MaxAttempts) {
                        Write-Information "ensureuser for $($Principal.Label) not resolvable yet (attempt $Attempt/$MaxAttempts), waiting for directory replication..."
                        Start-Sleep -Seconds 15
                    } else {
                        throw
                    }
                }
            }
            if (-not $EnsuredUser.Id) {
                throw 'Could not resolve principal on the site.'
            }
            $null = New-GraphPostRequest -uri "$AssignmentUri/addroleassignment(principalid=$($EnsuredUser.Id),roledefid=$RoleDefId)" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
            $Granted.Add($Principal.Label)
        } catch {
            $Failed.Add("$($Principal.Label) ($($_.Exception.Message))")
        }
    }

    $Messages = [System.Collections.Generic.List[string]]::new()
    if ($Granted.Count -gt 0) {
        $Messages.Add("Granted $PermissionLevel on $TargetLabel to $($Granted -join ', ').")
    }
    if ($Failed.Count -gt 0) {
        $Messages.Add("Failed for $($Failed -join '; ').")
    }
    if ($NotFound.Count -gt 0) {
        $Messages.Add("Not found by display name: $($NotFound -join ', ').")
    }
    $Result = $Messages -join ' '
    $Severity = if ($Granted.Count -gt 0) { 'Info' } else { 'Error' }
    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$SiteUrl : $Result" -sev $Severity

    if ($Granted.Count -eq 0) {
        throw $Result
    }
    return $Result
}
