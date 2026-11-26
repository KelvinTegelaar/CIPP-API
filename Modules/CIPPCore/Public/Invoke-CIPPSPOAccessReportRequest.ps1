function Invoke-CIPPSPOAccessReportRequest {
    <#
    .SYNOPSIS
        Calls the SharePoint Advanced Management access report API on a tenant's SharePoint admin site
    .DESCRIPTION
        The API behind Start-, Get-, Export- and Remove-SPODataAccessGovernanceInsight:
        {AdminUrl}/_api/v2.1/tenants/default/analyticsReports{Path}. Authenticates app-only with the SAM
        certificate. Requests Microsoft refuses (no SharePoint Advanced Management licence, a report
        already running, the re-run limit) throw ArgumentException, a missing report throws
        ItemNotFoundException, anything else throws untyped.

        -Content downloads a report's file and returns its bytes: a CSV for site permissions reports,
        a ZIP of one CSV per user for user permissions reports.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET', 'POST', 'DELETE')][string]$Method = 'GET',
        [string]$Body,
        [switch]$Content
    )

    $AdminUrl = (Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter).AdminUrl
    $Uri = "$AdminUrl/_api/v2.1/tenants/default/analyticsReports$Path"
    $Scope = "$AdminUrl/.default"
    Assert-CIPPSharePointHost -Uri $Uri -Scope $Scope
    if (-not (Get-AuthorisedRequest -Uri $Uri -TenantID $TenantFilter)) {
        throw (Get-AuthorisedRequestError -TenantID $TenantFilter -Context 'SharePoint report request')
    }
    $Headers = Get-GraphToken -tenantid $TenantFilter -scope $Scope -AsApp $true -UseCertificate
    $Headers['User-Agent'] = Get-CippUserAgent -SharePoint
    $Headers['Accept'] = 'application/json'

    if ($Content) {
        $Client = [System.Net.Http.HttpClient]::new()
        $Client.Timeout = [TimeSpan]::FromMinutes(10)
        # Disposing the client aborts a stalled download when the pipeline is stopped.
        $StopToken = $PSCmdlet.PipelineStopToken ?? $global:CraftPipelineStopToken
        $OnStop = if ($StopToken) { $StopToken.Register([Action]$Client.Dispose) }
        try {
            $Message = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)
            foreach ($Key in $Headers.Keys) { $null = $Message.Headers.TryAddWithoutValidation($Key, [string]$Headers[$Key]) }
            $Response = $Client.SendAsync($Message).GetAwaiter().GetResult()
            if ($Response.IsSuccessStatusCode) {
                return , $Response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            }
            $StatusCode = [int]$Response.StatusCode
            $ErrorBody = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        } finally {
            if ($OnStop) { $OnStop.Dispose() }
            $Client.Dispose()
        }
    } else {
        $Request = @{ Uri = $Uri; Method = $Method; Headers = $Headers; SkipHttpErrorCheck = $true; StatusCodeVariable = 'StatusCode' }
        if ($Body) { $Request.Body = $Body; $Request.ContentType = 'application/json' }
        $Result = Invoke-CIPPRestMethod @Request
        if ($StatusCode -lt 400) { return $Result }
        $ErrorBody = $Result
    }

    $Parsed = if ($ErrorBody -is [string]) { try { $ErrorBody | ConvertFrom-Json -ErrorAction Stop } catch { $null } } else { $ErrorBody }
    $ErrorText = if ($ErrorBody -is [string]) { $ErrorBody } else { ConvertTo-Json -InputObject $ErrorBody -Depth 5 -Compress }
    $Detail = $Parsed.error.message ?? $Parsed.errorMessage ?? $Parsed.ErrorMessage ?? $Parsed.message ?? $ErrorText

    if ($ErrorText -match 'MissingSAMLicense|ReportIsNotEnabled') {
        throw [System.ArgumentException]::new('SharePoint Advanced Management is not available in this tenant. It needs at least one user with a Microsoft 365 Copilot licence, or the SharePoint Advanced Management add-on.')
    }
    if ($ErrorText -match 'DAGReportAlreadyExists') {
        throw [System.ArgumentException]::new('A report of this type is already being generated. Wait for it to finish before starting another.')
    }
    if ($StatusCode -eq 404) {
        throw [System.Management.Automation.ItemNotFoundException]::new("The report was not found. It may have been deleted. $Detail")
    }
    if ($StatusCode -in 400, 409) {
        throw [System.ArgumentException]::new("Microsoft refused the request: $Detail")
    }
    throw "The SharePoint report request failed ($StatusCode): $Detail"
}
