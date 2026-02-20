function Get-CIPPAlertGlobalAdminAllowList {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $AllowedAdmins = @()
        $AlertEachAdmin = $false
        if ($InputValue -is [hashtable] -or $InputValue -is [pscustomobject]) {
            $AlertEachAdmin = [bool]($InputValue['AlertEachAdmin'])
            $ApprovedValue = if ($InputValue.ContainsKey('ApprovedGlobalAdmins') -or ($InputValue.PSObject.Properties.Name -contains 'ApprovedGlobalAdmins')) {
                $InputValue['ApprovedGlobalAdmins']
            } else {
                $null
            }
            $InputValue = $ApprovedValue
        }
        if ($null -ne $InputValue) {
            if ($InputValue -is [string]) {
                $AllowedAdmins = $InputValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            } elseif ($InputValue -is [System.Collections.IEnumerable]) {
                $AllowedAdmins = $InputValue | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }
            } else {
                $AllowedAdmins = @("$InputValue")
            }
        }
        $AllowedLookup = $AllowedAdmins | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique

        if (-not $AllowedLookup -or $AllowedLookup.Count -eq 0) {
            return
        }

        $GlobalAdmins = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members?`$select=id,displayName,userPrincipalName" -tenantid $TenantFilter -AsApp $true -ErrorAction Stop | Where-Object {
            $_.'@odata.type' -eq '#microsoft.graph.user' -and $_.displayName -ne 'On-Premises Directory Synchronization Service Account'
        }

        $UnapprovedAdmins = foreach ($admin in $GlobalAdmins) {
            if ([string]::IsNullOrWhiteSpace($admin.userPrincipalName)) { continue }
            $UpnPrefix = ($admin.userPrincipalName -split '@')[0].ToLowerInvariant()
            if ($AllowedLookup -notcontains $UpnPrefix) {
                [PSCustomObject]@{
                    Admin     = $admin
                    UpnPrefix = $UpnPrefix
                }
            }
        }

        if ($UnapprovedAdmins) {
            if ($AlertEachAdmin) {
                $AlertData = foreach ($item in $UnapprovedAdmins) {
                    $admin = $item.Admin
                    $UpnPrefix = $item.UpnPrefix
                    [PSCustomObject]@{
                        Message           = "$($admin.userPrincipalName) has Global Administrator role but is not in the approved allow list (prefix '$UpnPrefix')."
                        DisplayName       = $admin.displayName
                        UserPrincipalName = $admin.userPrincipalName
                        Id                = $admin.id
                        AllowedList       = if ($AllowedAdmins) { $AllowedAdmins -join ', ' } else { 'Not provided' }
                        Tenant            = $TenantFilter
                    }
                }
            } else {
                $NonCompliantUpns = @($UnapprovedAdmins.Admin.userPrincipalName)
                $AlertData = @([PSCustomObject]@{
                        Message           = "Found $($NonCompliantUpns.Count) Global Administrator account(s) not in the approved allow list."
                        NonCompliantUsers = $NonCompliantUpns -join ', '
                        ApprovedPrefixes  = if ($AllowedAdmins) { $AllowedAdmins -join ', ' } else { 'Not provided' }
                        Tenant            = $TenantFilter
                    })
            }

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to check approved Global Admins: $(Get-NormalizedError -message $_.Exception.Message)" -sev Error
    }
}
