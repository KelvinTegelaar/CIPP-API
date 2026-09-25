Function Invoke-ExecCreateTAP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $LifetimeInMinutes = $Request.Query.lifetimeInMinutes ?? $Request.Body.lifetimeInMinutes
    # Restrict the pass to a single use. New-CIPPTAP takes a [bool], and casting the
    # string 'false' yields $true, so this must be normalised before it is forwarded.
    $IsUsableOnce = ($Request.Query.isUsableOnce -eq $true) -or ($Request.Body.isUsableOnce -eq $true)
    $StartDateTime = $Request.Query.startDateTime ?? $Request.Body.startDateTime
    # Opt-in: most TAPs are used directly by the admin, so the pass is returned in plain text
    # unless the caller asks for a PwPush link. Same string-to-bool normalisation as above.
    $GeneratePwPushLink = ($Request.Query.generatePwPushLink -eq $true) -or ($Request.Body.generatePwPushLink -eq $true)

    try {
        # Create parameter hashtable for splatting
        $TAPParams = @{
            UserID             = $UserID
            TenantFilter       = $TenantFilter
            APIName            = $APIName
            Headers            = $Headers
            LifetimeInMinutes  = $LifetimeInMinutes
            IsUsableOnce       = $IsUsableOnce
            StartDateTime      = $StartDateTime
            GeneratePwPushLink = $GeneratePwPushLink
        }

        $TAPResult = New-CIPPTAP @TAPParams

        # Create results array with both TAP and UserID as separate items
        $Results = @(
            $TAPResult,
            @{
                resultText = "User ID: $UserID"
                copyField  = $UserID
                state      = 'success'
            }
        )

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Results }
        })

}
