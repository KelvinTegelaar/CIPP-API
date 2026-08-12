
function Invoke-ExecAzBobbyTables {
    <#
    .SYNOPSIS
        Execute a AzBobbyTables function
    .DESCRIPTION
        This function is used to interact with Azure Tables. This is advanced functionality used for external integrations or SuperAdmin functionality.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $AllowList = @(
        'Add-AzDataTableEntity'
        'Add-CIPPAzDataTableEntity'
        'Update-AzDataTableEntity'
        'Get-AzDataTableEntity'
        'Get-CIPPAzDataTableEntity'
        'Get-AzDataTable'
        'New-AzDataTable'
        'Remove-CIPPAzDataTableEntity'
        'Remove-AzDataTable'
        'Remove-AzDataTableEntity'
    )

    $Function = $Request.Body.FunctionName
    $Params = if ($Request.Body.Parameters) {
        $Request.Body.Parameters | ConvertTo-Json -Compress -ErrorAction Stop | ConvertFrom-Json -AsHashtable
    } else {
        @{}
    }

    if ($Function -in $AllowList) {
        if ($Function -eq 'Get-AzDataTable') {
            $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage
        } else {
            $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName $Request.Body.TableName
        }
        try {
            $Results = & $Function -Context $Context @Params
            if (!$Results) {
                $Results = "Function $Function executed successfully"
            }
            # Drop it from the Get-CIPPTable cache so it gets recreated on next use. The table
            # name comes from the request, so clear everything when it was not supplied.
            if ($Function -eq 'Remove-AzDataTable') {
                if ($Request.Body.TableName) {
                    Unregister-CIPPTable -TableName $Request.Body.TableName
                } else {
                    Unregister-CIPPTable -All
                }
            }
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $Results = $_.Exception.Message
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    } else {
        $Results = "Function $Function not found or not allowed"
        $StatusCode = [HttpStatusCode]::NotFound
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
