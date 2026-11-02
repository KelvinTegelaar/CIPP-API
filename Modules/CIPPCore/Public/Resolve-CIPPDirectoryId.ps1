function Resolve-CIPPDirectoryId {
    <#
    .SYNOPSIS
    Resolves directory identities to canonical Graph object ids.

    .DESCRIPTION
    Accepts object ids, UPNs, mail addresses, or other Graph-addressable keys and returns
    the corresponding directory object for each. Used so membership, ownership, and
    ManagedBy compare/write always operate on ids — for users, groups, and other
    directory objects — matching ListGroups/EditGroup.

    GUID-shaped values are resolved via directoryObjects/getByIds (any directory type).
    Misses fall back to users/{id} then groups/{id}.
    Non-GUID values try users/{identity}, then groups filtered by mail/mailNickname.

    .PARAMETER Identity
    One or more identities to resolve.

    .PARAMETER TenantFilter
    Tenant id or default domain.

    .OUTPUTS
    One PSCustomObject per input:
      Input, Id, UserPrincipalName, DisplayName, Mail, MailNickname,
      ODataType, Type, ExchangeIdentity, Label, Resolved

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Identity,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Identities = @(
        $Identity |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Select-Object -Unique
    )
    if ($Identities.Count -eq 0) {
        return @()
    }

    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $Guids = @($Identities | Where-Object { $_ -match $GuidPattern })
    $Others = @($Identities | Where-Object { $_ -notmatch $GuidPattern })

    $ResolvedByInput = @{}

    $NewResolved = {
        param($InputKey, $Obj)
        $ODataType = $Obj.'@odata.type'
        $Type = switch -Regex ($ODataType) {
            'user$' { 'User'; break }
            'group$' { 'Group'; break }
            'servicePrincipal$' { 'ServicePrincipal'; break }
            'orgContact$' { 'OrgContact'; break }
            default {
                if ($Obj.userPrincipalName) { 'User' }
                elseif ($null -ne $Obj.mailEnabled -or $null -ne $Obj.groupTypes) { 'Group' }
                else { 'DirectoryObject' }
            }
        }
        $Label = $Obj.displayName ?? $Obj.userPrincipalName ?? $Obj.mail ?? $InputKey
        # EXO Member/ManagedBy accepts SMTP, UPN, alias, or GUID
        $ExchangeIdentity = $Obj.mail ?? $Obj.userPrincipalName ?? $Obj.mailNickname ?? $Obj.id
        [pscustomobject]@{
            Input             = $InputKey
            Id                = $Obj.id
            UserPrincipalName = $Obj.userPrincipalName
            DisplayName       = $Obj.displayName
            Mail              = $Obj.mail
            MailNickname      = $Obj.mailNickname
            ODataType         = $ODataType
            Type              = $Type
            ExchangeIdentity  = $ExchangeIdentity
            Label             = $Label
            Resolved          = $true
        }
    }.GetNewClosure()

    if ($Guids.Count -gt 0) {
        for ($i = 0; $i -lt $Guids.Count; $i += 1000) {
            $Chunk = @($Guids[$i..([Math]::Min($i + 999, $Guids.Count - 1))])
            try {
                $Body = @{ ids = $Chunk } | ConvertTo-Json -Compress
                $ByIds = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,displayName,userPrincipalName,mail,mailNickname,mailEnabled,groupTypes' -tenantid $TenantFilter -body $Body
                foreach ($Obj in @($ByIds.value ?? $ByIds)) {
                    if (-not $Obj.id) { continue }
                    $ResolvedByInput[$Obj.id] = & $NewResolved -InputKey $Obj.id -Obj $Obj
                }
            } catch {
                Write-Information "Resolve-CIPPDirectoryId: getByIds failed: $($_.Exception.Message)"
            }

            $MissingGuids = @($Chunk | Where-Object { -not $ResolvedByInput.ContainsKey($_) })
            if ($MissingGuids.Count -gt 0) {
                $FallbackRequests = foreach ($g in $MissingGuids) {
                    @(
                        @{
                            id     = "user-$g"
                            method = 'GET'
                            url    = "users/$g`?`$select=id,userPrincipalName,displayName,mail,mailNickname"
                        }
                        @{
                            id     = "group-$g"
                            method = 'GET'
                            url    = "groups/$g`?`$select=id,displayName,mail,mailNickname,mailEnabled,groupTypes"
                        }
                    )
                }
                $FallbackResults = New-GraphBulkRequest -Requests @($FallbackRequests) -tenantid $TenantFilter
                foreach ($g in $MissingGuids) {
                    $Hit = $FallbackResults | Where-Object {
                        ($_.id -eq "user-$g" -or $_.id -eq "group-$g") -and
                        $_.status -ge 200 -and $_.status -le 299 -and $_.body.id
                    } | Select-Object -First 1
                    if ($Hit) {
                        $ResolvedByInput[$g] = & $NewResolved -InputKey $g -Obj $Hit.body
                    }
                }
            }
        }
    }

    if ($Others.Count -gt 0) {
        $OtherRequests = foreach ($o in $Others) {
            $Encoded = if ($o -like '*#EXT#*') { [System.Web.HttpUtility]::UrlEncode($o) } else { $o }
            @{
                id     = "user-$o"
                method = 'GET'
                url    = "users/$Encoded`?`$select=id,userPrincipalName,displayName,mail,mailNickname"
            }
        }
        $OtherResults = New-GraphBulkRequest -Requests @($OtherRequests) -tenantid $TenantFilter
        $StillMissing = [System.Collections.Generic.List[string]]::new()
        foreach ($Result in $OtherResults) {
            $InputKey = $Result.id -replace '^user-', ''
            if ($Result.status -ge 200 -and $Result.status -le 299 -and $Result.body.id) {
                $ResolvedByInput[$InputKey] = & $NewResolved -InputKey $InputKey -Obj $Result.body
            } else {
                $StillMissing.Add($InputKey)
            }
        }

        # Non-user mail/alias → group lookup (ListUsersAndGroups can surface nested groups by id,
        # but CSV / EXO-style addresses need mail or mailNickname).
        foreach ($o in $StillMissing) {
            $Escaped = $o.Replace("'", "''")
            try {
                $Filter = [System.Uri]::EscapeDataString("mail eq '$Escaped' or mailNickname eq '$Escaped'")
                $GroupHits = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=$Filter&`$select=id,displayName,mail,mailNickname,mailEnabled,groupTypes&`$top=2" -tenantid $TenantFilter
                $GroupObj = @($GroupHits) | Select-Object -First 1
                if ($GroupObj.id) {
                    $ResolvedByInput[$o] = & $NewResolved -InputKey $o -Obj $GroupObj
                }
            } catch {
                Write-Information "Resolve-CIPPDirectoryId: group filter failed for '$o': $($_.Exception.Message)"
            }
        }
    }

    foreach ($Original in $Identities) {
        if ($ResolvedByInput.ContainsKey($Original)) {
            $ResolvedByInput[$Original]
        } else {
            [pscustomobject]@{
                Input             = $Original
                Id                = $null
                UserPrincipalName = $null
                DisplayName       = $null
                Mail              = $null
                MailNickname      = $null
                ODataType         = $null
                Type              = $null
                ExchangeIdentity  = $null
                Label             = $Original
                Resolved          = $false
            }
        }
    }
}
