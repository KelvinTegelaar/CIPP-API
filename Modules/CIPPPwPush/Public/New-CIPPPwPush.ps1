function New-CIPPPwPush {
    <#
    .SYNOPSIS
        Creates a text push on a Password Pusher server.
    .DESCRIPTION
        Posts the payload to /p.json (v1) or /api/v2/pushes (v2), sending only the optional fields
        that were set (retrieval step and deletable-by-viewer are always sent), and returns the share link and push id.
    .PARAMETER Connection
        Object with BaseUrl, Headers and ApiVersion, built per call by the caller.
    .PARAMETER WorkspaceId
        Workspace/account id; kept as a string because ids look like 'acct_...'.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][string]$Payload,
        [ValidateRange(1, 90)][int]$ExpireAfterDays,
        [ValidateRange(1, 100)][int]$ExpireAfterViews,
        [bool]$DeletableByViewer = $false,
        [bool]$RetrievalStep = $false,
        [string]$Passphrase,
        [string]$WorkspaceId
    )

    $Push = [ordered]@{ payload = $Payload; kind = 'text' }
    if ($PSBoundParameters.ContainsKey('ExpireAfterDays')) { $Push.expire_after_days = $ExpireAfterDays }
    if ($PSBoundParameters.ContainsKey('ExpireAfterViews')) { $Push.expire_after_views = $ExpireAfterViews }
    # Always sent: servers apply their own default when these are omitted
    $Push.deletable_by_viewer = $DeletableByViewer
    $Push.retrieval_step = $RetrievalStep
    if (-not [string]::IsNullOrEmpty($Passphrase)) { $Push.passphrase = $Passphrase }

    # Same push fields on both versions; only the wrapper, id field and path differ
    if ($Connection.ApiVersion -eq 'v2') {
        $Path = 'api/v2/pushes'
        $Body = [ordered]@{ push = $Push }
        if (-not [string]::IsNullOrEmpty($WorkspaceId)) { $Body.workspace_id = $WorkspaceId }
    } else {
        $Path = 'p.json'
        $Body = [ordered]@{ password = $Push }
        if (-not [string]::IsNullOrEmpty($WorkspaceId)) { $Body.account_id = $WorkspaceId }
    }

    if (-not $PSCmdlet.ShouldProcess($Connection.BaseUrl, 'Create PWPush text push')) { return }

    $Response = Invoke-CIPPPwPushRequest -Uri "$($Connection.BaseUrl)/$Path" -Method POST -Headers $Connection.Headers -Body ($Body | ConvertTo-Json -Depth 5 -Compress)

    $Link = if (-not [string]::IsNullOrEmpty($Response.html_url)) {
        $Response.html_url
    } elseif (-not [string]::IsNullOrEmpty($Response.url_token)) {
        "$($Connection.BaseUrl)/p/$($Response.url_token)$(if ($RetrievalStep) { '/r' })"
    } else {
        throw 'PWPush API response did not contain a link'
    }
    [pscustomobject]@{ Link = $Link; UrlToken = $Response.url_token }
}
