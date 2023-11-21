function Invoke-TestResults {

    Push-OutputBinding -Name QueueItem -Value ([pscustomobject]@{
            FunctionName = 'TestResults'
            Body         = @{
                Permissions = $true
                Tenants     = $true
                GDAP        = $true
            }
        })
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = "yes"
        })

}