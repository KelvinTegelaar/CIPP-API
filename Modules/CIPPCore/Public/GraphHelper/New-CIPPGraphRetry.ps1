function New-CIPPGraphRetry {
    <#
    .SYNOPSIS
        Retries a failed Graph API request
    .DESCRIPTION
        This function is called by scheduled tasks when a Graph API request has exhausted retries.
        It attempts to execute the request again with the original parameters.
    .PARAMETER uri
        The Graph API URI to call
    .PARAMETER tenantid
        The tenant ID for the request
    .PARAMETER type
        The HTTP method (POST, PATCH, DELETE, etc.)
    .PARAMETER body
        The request body
    .PARAMETER scope
        Optional OAuth scope
    .PARAMETER AsApp
        Whether to use application authentication
    .PARAMETER NoAuthCheck
        Whether to skip authorization check
    .PARAMETER skipTokenCache
        Whether to skip token cache
    .PARAMETER AddedHeaders
        Additional headers to include
    .PARAMETER contentType
        Content type for the request
    .PARAMETER IgnoreErrors
        Whether to ignore HTTP errors
    .PARAMETER returnHeaders
        Whether to return response headers
    .PARAMETER maxRetries
        Maximum number of retries
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$uri,

        [Parameter(Mandatory = $true)]
        [string]$tenantid,

        [Parameter(Mandatory = $true)]
        [string]$type,

        [string]$body,
        [string]$scope,
        [switch]$AsApp,
        [switch]$NoAuthCheck,
        [switch]$skipTokenCache,
        [hashtable]$AddedHeaders,
        [string]$contentType,
        [bool]$IgnoreErrors,
        [bool]$returnHeaders,
        [int]$maxRetries = 3
    )

    Write-Information "Retrying Graph API request for URI: $uri | Tenant: $tenantid"

    try {
        # Build the parameter splat for New-GraphPOSTRequest
        $GraphParams = @{
            uri           = $uri
            tenantid      = $tenantid
            type          = $type
            body          = $body
            maxRetries    = $maxRetries
            ScheduleRetry = $false  # Do NOT schedule again if this retry fails
        }

        # Add optional parameters if they were provided
        if ($scope) { $GraphParams.scope = $scope }
        if ($AsApp) { $GraphParams.AsApp = $AsApp }
        if ($NoAuthCheck) { $GraphParams.NoAuthCheck = $NoAuthCheck }
        if ($skipTokenCache) { $GraphParams.skipTokenCache = $skipTokenCache }
        if ($AddedHeaders) { $GraphParams.AddedHeaders = $AddedHeaders }
        if ($contentType) { $GraphParams.contentType = $contentType }
        if ($IgnoreErrors) { $GraphParams.IgnoreErrors = $IgnoreErrors }
        if ($returnHeaders) { $GraphParams.returnHeaders = $returnHeaders }

        # Execute the Graph request
        $Result = New-GraphPOSTRequest @GraphParams

        Write-LogMessage -API 'GraphRetry' -message "Successfully retried Graph request for URI: $uri | Tenant: $tenantid" -Sev 'Info' -tenant $tenantid

        return $Result
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'GraphRetry' -message "Failed to retry Graph request for URI: $uri | Tenant: $tenantid. Error: $ErrorMessage" -Sev 'Error' -tenant $tenantid
        throw $ErrorMessage
    }
}
