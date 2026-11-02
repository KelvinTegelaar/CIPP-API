function Set-CippUserAgentContext {
    <#
    .SYNOPSIS
        Stores the execution source and user identity for the current invocation, for inclusion in outbound User-Agent strings.
    .DESCRIPTION
        Resolves the acting identity from the client principal headers (UPN when available, falling back to
        the Entra object id claim, SWA userId, or the API client AppId) and stores it with the action source in
        AsyncLocal storage so Get-CippUserAgent can build an attributable User-Agent for Graph requests.
    .PARAMETER Headers
        The request headers (live or stored snapshot) containing x-ms-client-principal* values.
    .PARAMETER Source
        The action source label, e.g. 'scheduled-task'. When omitted, 'api' is inferred for AAD API clients and 'user' otherwise.
    .PARAMETER TaskId
        Optional task identifier (e.g. the scheduled task RowKey) included in the User-Agent for cross-referencing.
    .PARAMETER TemplateId
        Optional standard template identifier included in the User-Agent for cross-referencing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Headers,
        [string]$Source,
        [string]$TaskId,
        [string]$TemplateId
    )

    if (-not $script:CippUserAgentContextStorage) {
        $script:CippUserAgentContextStorage = [System.Threading.AsyncLocal[hashtable]]::new()
    }

    $Identity = $null
    $GuidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    if ($Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Headers.'x-ms-client-principal-name' -match $GuidRegex) {
        # Direct API client - principal name is the AppId
        $Identity = $Headers.'x-ms-client-principal-name'
        if (-not $Source) { $Source = 'api' }
    } elseif ($Headers.'x-ms-client-principal') {
        try {
            $Principal = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json
            # Prefer the UPN - human readable and meaningful to MDR/security teams reviewing M365 audit logs
            $Upn = $Principal.userDetails
            if ([string]::IsNullOrWhiteSpace($Upn)) {
                $Upn = ($Principal.claims | Where-Object { $_.typ -in @('preferred_username', 'upn', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn', 'email', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') } | Select-Object -First 1).val
            }
            if ($Upn) {
                $Identity = $Upn
                if (-not $Source) { $Source = 'user' }
            } else {
                $AppId = ($Principal.claims | Where-Object { $_.typ -in @('azp', 'appid') } | Select-Object -First 1).val
                if ($AppId) {
                    # App-only token - identify by AppId
                    $Identity = $AppId
                    if (-not $Source) { $Source = 'api' }
                } else {
                    # Fall back to the Entra object id claim or the SWA userId
                    $Oid = ($Principal.claims | Where-Object { $_.typ -in @('http://schemas.microsoft.com/identity/claims/objectidentifier', 'oid') } | Select-Object -First 1).val
                    $Identity = $Oid ?? $Principal.userId
                    if (-not $Source) { $Source = 'user' }
                }
            }
        } catch {
            Write-Verbose "Failed to resolve identity from client principal: $($_.Exception.Message)"
        }
    }

    if ($Source) {
        $script:CippUserAgentContextStorage.Value = @{
            Source     = $Source
            Identity   = $Identity
            TaskId     = $TaskId
            TemplateId = $TemplateId
        }
    }
}
