function Invoke-ExecTestRefresh {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Tests.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        $TestName = $Request.Query.testName ?? $Request.Body.testName
        $Function = 'Invoke-CippTest{0}' -f $TestName
        if (Get-Command -Name $Function -Module 'CIPPTests' -ErrorAction SilentlyContinue) {
            $TestResult = & $Function -Tenant $TenantFilter
            $Table = Get-CippTable -tablename 'CippTestResults'
            Add-CIPPAzDataTableEntity @Table -Entity $TestResult -Force
            $StatusCode = [HttpStatusCode]::OK
            $Body = [PSCustomObject]@{ Results = "Successfully updated test $TestName for tenant $TenantFilter"; Metadata = $TestResult }
        } else {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Message = "Test function not found: $Function" }
                })
        }
    } catch {
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{
            Message = "Failed to update test $TestName for $TenantFilter"
            Error   = Get-CippException -Exception $_
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
