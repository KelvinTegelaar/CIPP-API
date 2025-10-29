function Invoke-PublicPhishingCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    [CmdletBinding()]

    #this has been switched to the external free service by cyberdrain at clone.cipp.app due to extreme numbers of executions if selfhosted.
    param($Request, $TriggerMetadata)

    $Tenant = Get-Tenants -TenantFilter $Request.body.TenantId

    if ($Request.body.Cloned -and $Tenant.customerId -eq $Request.body.TenantId) {
        Write-AlertMessage -message $Request.body.AlertMessage -sev 'Alert' -tenant $Request.body.TenantId
    } elseif ($Request.Body.source -and $Tenant) {
        $table = Get-CIPPTable -tablename CheckExtensionAlerts
        $Message = "Alert received from $($Request.Body.source) for $($Request.body.TenantId)"
        $ID = (New-Guid).GUID
        $TableBody = @{
            RowKey                   = "$ID"
            PartitionKey             = [string]$Tenant.defaultDomainName
            tenantFilter             = [string]$Tenant.defaultDomainName
            message                  = [string]$Message
            type                     = [string]$request.body.type
            url                      = [string]$request.body.url
            reason                   = [string]$request.body.reason
            score                    = [string]$request.body.score
            threshold                = [string]$request.body.threshold
            potentialUserName        = [string]$request.body.userEmail
            potentialUserDisplayName = [string]$request.body.userDisplayName
            reportedByIP             = [string]$Request.headers.'x-forwarded-for'
            rawBody                  = "$($Request.body | ConvertTo-Json)"
        }
        $null = Add-CIPPAzDataTableEntity @table -Entity $TableBody -Force
        Write-AlertTrace -cmdletName 'CheckExtentionAlert' -tenantFilter $Tenant.defaultDomainName -data $TableBody
        #Write-AlertMessage -message $Message -sev 'Alert' -tenant $Tenant.customerId -LogData $Request.body
    }

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = 'OK'
        }
}
