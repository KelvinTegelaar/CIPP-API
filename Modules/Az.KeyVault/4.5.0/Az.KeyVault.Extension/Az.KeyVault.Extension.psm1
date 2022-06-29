# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

function Check-SubscriptionLogIn
{
    param (
        [object] $SubscriptionId,
        [object] $AzKVaultName
    )

    if("string" -ne $SubscriptionId.GetType().Name)
    {
        throw "The type of SubscriptionId should be string, current is " + $SubscriptionId.GetType().Name + ". Please check registration information by 'Get-SecretVault | fl'"
    }

    if("string" -ne $AzKVaultName.GetType().Name)
    {
        throw "The type of AzKVaultName should be string, current is " + $AzKVaultName.GetType().Name + ". Please check registration information by 'Get-SecretVault | fl'"
    }

    $azContext = Az.Accounts\Get-AzContext
    if (($null -eq $azContext) -or ($azContext.Subscription.Id -ne $SubscriptionId))
    {
        try
        {
            Set-AzContext -SubscriptionId ${SubscriptionId} -ErrorAction Stop
        }
        catch
        {
            throw $_.ToString() + "To use Azure vault named '${AzKVaultName}', please try 'Connect-AzAccount -SubscriptionId {SubscriptionId}' to log into Azure account subscription '${SubscriptionId}'." 
        }
    }
}

function Get-Secret
{
    param (
        [string] $Name,
        [string] $VaultName,
        [hashtable] $AdditionalParameters
    )

    $secret = Az.KeyVault\Get-AzKeyVaultSecret -Name $Name -VaultName $AdditionalParameters.AZKVaultName
    if ($null -ne $secret)
    {
        switch ($secret.ContentType) {
            'ByteArray' 
            {  
                $SecretValue = Get-ByteArray $Secret
            }
            'String'
            {
                $SecretValue = Get-String $Secret
            }
            'PSCredential' 
            {
                $SecretValue = Get-PSCredential $Secret
            }
            'Hashtable' 
            {  
                $SecretValue = Get-Hashtable $Secret
            }
            Default 
            {
                $SecretValue = Get-SecureString $Secret
            }
        }
        return $SecretValue
    }
}

function Get-ByteArray
{
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object] $Secret
    )
    $secretValueText = Get-String $Secret
    return [System.Text.Encoding]::ASCII.GetBytes($secretValueText)
}

function Get-String
{
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object] $Secret
    )

    $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret.SecretValue)
    try {
        $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
    }
    return $secretValueText
}

function Get-SecureString
{
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object] $Secret
    )

    return $Secret.SecretValue
}

function Get-PSCredential
{
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object] $Secret
    )

    $secretHashTable = Get-Hashtable $Secret
    return [System.Management.Automation.PSCredential]::new($secretHashTable["UserName"], ($secretHashTable["Password"] | ConvertTo-SecureString -AsPlainText -Force)) 
}

function Get-Hashtable
{
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [object] $Secret
    )

    $jsonObject = Get-String $Secret | ConvertFrom-Json
    $hashtable = @{}
    $jsonObject.psobject.Properties | foreach { $hashtable[$_.Name] = $_.Value }
    return $hashtable
}

function Set-Secret
{
    param (
        [string] $Name,
        [object] $Secret,
        [string] $VaultName,
        [hashtable] $AdditionalParameters
    )

    switch ($Secret.GetType().Name) {
        'Byte[]' 
        {
            Set-ByteArray -Name $Name -Secret $Secret -AZKVaultName $AdditionalParameters.AZKVaultName -ContentType 'ByteArray'
        }
        'String'
        {
            Set-String -Name $Name -Secret $Secret -AZKVaultName $AdditionalParameters.AZKVaultName -ContentType 'String'
        }
        'SecureString'
        {
            Set-SecureString -Name $Name -Secret $Secret -AZKVaultName $AdditionalParameters.AZKVaultName -ContentType 'SecureString'
        }
        'PSCredential' 
        {
            Set-PSCredential -Name $Name -Secret $Secret -AZKVaultName $AdditionalParameters.AZKVaultName -ContentType 'PSCredential'
        }
        'Hashtable' 
        {  
            Set-Hashtable -Name $Name -Secret $Secret -AZKVaultName $AdditionalParameters.AZKVaultName -ContentType 'Hashtable'
        }
        Default
        {
            throw "Invalid type. Types supported: byte[], string, SecureString, PSCredential, Hashtable";
        }
    }

    return $?
}

function Set-ByteArray
{
    param (
        [string] $Name,
        [Byte[]] $Secret,
        [string] $AZKVaultName,
        [string] $ContentType
    )

    $SecretString = [System.Text.Encoding]::ASCII.GetString($Secret)
    Set-String -Name $Name -Secret $SecretString -AZKVaultName $AZKVaultName -ContentType $ContentType
}

function Set-String
{
    param (
        [string] $Name,
        [string] $Secret,
        [string] $AZKVaultName,
        [string] $ContentType
    )
    $SecureSecret = ConvertTo-SecureString -String $Secret -AsPlainText -Force
    $null = Az.KeyVault\Set-AzKeyVaultSecret -Name $Name -SecretValue $SecureSecret -VaultName $AZKVaultName -ContentType $ContentType
}

function Set-SecureString
{
    param (
        [string] $Name,
        [SecureString] $Secret,
        [string] $AZKVaultName,
        [string] $ContentType
    )
    
    $null = Az.KeyVault\Set-AzKeyVaultSecret -Name $Name -SecretValue $Secret -VaultName $AZKVaultName -ContentType $ContentType
}

function Set-PSCredential
{
    param (
        [string] $Name,
        [PSCredential] $Secret,
        [string] $AZKVaultName,
        [string] $ContentType
    )
    $secretHashTable = @{"UserName" = $Secret.UserName; "Password" = $Secret.GetNetworkCredential().Password}
    $SecretString = ConvertTo-Json $secretHashTable
    Set-String -Name $Name -Secret $SecretString -AZKVaultName $AZKVaultName -ContentType $ContentType
}

function Set-Hashtable
{
    param (
        [string] $Name,
        [Hashtable] $Secret,
        [string] $AZKVaultName,
        [string] $ContentType
    )
    $SecretString = ConvertTo-Json $Secret
    Set-String -Name $Name -Secret $SecretString -AZKVaultName $AZKVaultName -ContentType $ContentType
}

function Remove-Secret
{
    param (
        [string] $Name,
        [string] $VaultName,
        [hashtable] $AdditionalParameters
    )

    $null = Az.KeyVault\Remove-AzKeyVaultSecret -Name $Name -VaultName $AdditionalParameters.AZKVaultName -Force
    return $?
}

function Get-SecretInfo
{
    param (
        [string] $Filter,
        [string] $VaultName,
        [hashtable] $AdditionalParameters
    )
   
    if ([string]::IsNullOrEmpty($Filter))
    {
        $Filter = "*"
    }

    $pattern = [WildcardPattern]::new($Filter)

    $vaultSecretInfos = Az.KeyVault\Get-AzKeyVaultSecret -VaultName $AdditionalParameters.AZKVaultName

    foreach ($vaultSecretInfo in $vaultSecretInfos)
    {
        if ($pattern.IsMatch($vaultSecretInfo.Name))
        {
            [Microsoft.PowerShell.SecretManagement.SecretType]$secretType = New-Object Microsoft.PowerShell.SecretManagement.SecretType
            if (![System.Enum]::TryParse($vaultSecretInfo.ContentType, $true, [ref]$secretType))
            {
                $secretType = "Unknown"
            }
            Write-Output (
                [Microsoft.PowerShell.SecretManagement.SecretInformation]::new(
                    $vaultSecretInfo.Name,
                    $secretType,
                    $VaultName)
            )
        }
    }
}

function Test-SecretVault
{
    param (
        [string] $VaultName,
        [hashtable] $AdditionalParameters
    )

    try
    {
        Check-SubscriptionLogIn $AdditionalParameters.SubscriptionId $AdditionalParameters.AZKVaultName
    }
    catch
    {
        Write-Error $_
        return $false
    }

    return $true
}
# SIG # Begin signature block
# MIInrQYJKoZIhvcNAQcCoIInnjCCJ5oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCyKy+DlRs3fTBA
# u5XhgR3udHDfTLCuiuI7TkzA4f8+cKCCDYEwggX/MIID56ADAgECAhMzAAACUosz
# qviV8znbAAAAAAJSMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDQ5M+Ps/X7BNuv5B/0I6uoDwj0NJOo1KrVQqO7ggRXccklyTrWL4xMShjIou2I
# sbYnF67wXzVAq5Om4oe+LfzSDOzjcb6ms00gBo0OQaqwQ1BijyJ7NvDf80I1fW9O
# L76Kt0Wpc2zrGhzcHdb7upPrvxvSNNUvxK3sgw7YTt31410vpEp8yfBEl/hd8ZzA
# v47DCgJ5j1zm295s1RVZHNp6MoiQFVOECm4AwK2l28i+YER1JO4IplTH44uvzX9o
# RnJHaMvWzZEpozPy4jNO2DDqbcNs4zh7AWMhE1PWFVA+CHI/En5nASvCvLmuR/t8
# q4bc8XR8QIZJQSp+2U6m2ldNAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUNZJaEUGL2Guwt7ZOAu4efEYXedEw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDY3NTk3MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAFkk3
# uSxkTEBh1NtAl7BivIEsAWdgX1qZ+EdZMYbQKasY6IhSLXRMxF1B3OKdR9K/kccp
# kvNcGl8D7YyYS4mhCUMBR+VLrg3f8PUj38A9V5aiY2/Jok7WZFOAmjPRNNGnyeg7
# l0lTiThFqE+2aOs6+heegqAdelGgNJKRHLWRuhGKuLIw5lkgx9Ky+QvZrn/Ddi8u
# TIgWKp+MGG8xY6PBvvjgt9jQShlnPrZ3UY8Bvwy6rynhXBaV0V0TTL0gEx7eh/K1
# o8Miaru6s/7FyqOLeUS4vTHh9TgBL5DtxCYurXbSBVtL1Fj44+Od/6cmC9mmvrti
# yG709Y3Rd3YdJj2f3GJq7Y7KdWq0QYhatKhBeg4fxjhg0yut2g6aM1mxjNPrE48z
# 6HWCNGu9gMK5ZudldRw4a45Z06Aoktof0CqOyTErvq0YjoE4Xpa0+87T/PVUXNqf
# 7Y+qSU7+9LtLQuMYR4w3cSPjuNusvLf9gBnch5RqM7kaDtYWDgLyB42EfsxeMqwK
# WwA+TVi0HrWRqfSx2olbE56hJcEkMjOSKz3sRuupFCX3UroyYf52L+2iVTrda8XW
# esPG62Mnn3T8AuLfzeJFuAbfOSERx7IFZO92UPoXE1uEjL5skl1yTZB3MubgOA4F
# 8KoRNhviFAEST+nG8c8uIsbZeb08SeYQMqjVEmkwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZgjCCGX4CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgzfjGQWbV
# 8PWkq/j6esCPbG8eEVUFC89qCcqsnpSYohowQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBRlqRWT9wttcBnIyReglxxwE0oIyd/BknFK552NDfN
# yhc/MGwi25lVNLjmhZ3bohKOBbWGtUZUHjPwWC0lU47vbJgYCJ8Dq7Wpi4ywZg+A
# /CVBecH4RNI72LKReKjhl8uYPel9qYAqC/J1YRZn/lQFSoC0JIh6N+xQ6bXnOWRF
# darQHk+z88LbPLTERPNUv+tNrmwHO2Ot/vcIu1sHOZa6zdBxNdGRKNsClSma08by
# Q5DjUUkHX97Mjl+sC9Q+g6YgvPUr9OkWKgIQLSj9ErloyON0bYH4a+26eHoP3V1n
# Yoxl9rzX+RlfpPODEJu9/EIcsmMyzL8ziNFQH/G6K1eUoYIXDDCCFwgGCisGAQQB
# gjcDAwExghb4MIIW9AYJKoZIhvcNAQcCoIIW5TCCFuECAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIJ4IVs50jWPD23twoaLqoHVvQVj/oZKtItaWRT30
# 4cxiAgZihMo8YEEYEzIwMjIwNTIwMDcxMjEzLjA3NVowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjpGODdBLUUzNzQtRDdCOTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEV8wggcQMIIE+KADAgECAhMzAAABrqoLXLM0pZUaAAEA
# AAGuMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTEzN1oXDTIzMDUxMTE4NTEzN1owgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGODdB
# LUUzNzQtRDdCOTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJOMGvEhNQwLHactznPp
# Y8Jg5qI8Qsgp0mhl2G2ztVPonq4gsOMe5u9p5f17PIM1KXjUaKNl3djncq29Liqm
# qnaKORggPHNEk7Q+tal5Iyc+S8k/R31gCGt4qvQVqBLQNivxOukUfapG41LTdLHe
# M4uwInk+QrGQH2K4wjNtiUpirF2PdCcbkXyALEpyT2RrwzJmzcmbdCscY0N3RHxr
# MeWQ3k7sNt41NBZOT+4pCmkw8UkgKiSJXMzKs38MxUqx/OlS80dLDTHd+Zei1S1/
# qbCtTGzNm0bj6qfklUM3JFAF1JLXwwvqgZRdDQU6224wtGnwalTaOI0R0eX+crcP
# pXGB27EIgYU+0lo2aH79SNrsPWEcdBICd0yfhFU2niVJepGzkXetJvbFxW3iN7sc
# jLfw/S6UXF7wtEzdONXViI5P2UM779P6EIZ+g81E2MWX8XjLVyvIsvzyckJ4FFi+
# h1yPE+vzckPxzHOsiLaafucsyMjAaAM8Wwa+02BujEOylfLSyk0iv9IvSI9ZkJW/
# gLvQ42U0+U035ZhUhCqbKEWEMIr2ya2rYprUMEKcXf4R97LVPBfsJnbkNUubpUA4
# K1i7ijQ1pkUlt+YQ/34mtEy7eSigVpVznqfrNVerCvHG5IwfeFVhPNbAwK6lBEQ2
# 9nMYjRXj4QLyvmKRmqOJM/w1AgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQU0zBv378o
# YIrBqa10/vztZDphUe4wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAXb+R8P1VAEQOPK0zAxADIXP4cJQmartjVFLM
# EkLYh39PFtVbt84Rv0Q1GSTYmhP8f/OOvnmC5ejw3Nc1VRi74rWGUITv18Wqr8eB
# vASd4eDAxFbA8knOOm/ZySkMDDYdb6738aQ0yvqf7AWchgPntCc/nhNapSJmjzUk
# e7EvjB8ei0BnY0xl+AQcSxJG/Vnsm9IwOer8E1miVLYfPn9fIDdaav1bq9i+gnZf
# 1hS7apGpxbitCJr1KGD4jIyABkxHheoPOhhtQm1uznE7blKxH8pU7W2A+eqggsNk
# M3VB0nrzRZBqm4SmBSNhOPzy3ofOmLcRK/aloOAr6nehi8i5lhmTg1LkOAxChLwH
# vluiCY9K+2vIpt48ioK/h+tz5RgVdb+S8xwn728lN8KPkkB2Ra5iicrvtgA55wSU
# dh6FFxXxeS+bsgBayn7ZyafTpDM7BQOBYwaodsuVf5XgGryGx84k4R58mPwB3Q09
# CRAGs35NOt6TrPXqcylNu6Zz8xTQDcaJp54pKyOoW5iIDFjpLneXTEjtWCFCgAo4
# zbp9CNITp97KPnc3gZVaMvEpU8Sp7VZwN9ckR2WDKyOjDghIcfuFJTLOdkOuMLGs
# WPdnY6idtWc2bUDQa2QbzmNSZyFthEprwQ2GmgaGbGKuYVVqUj/Yt21HD0PBeDI5
# Mal8ScwwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
# DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIw
# MAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAx
# MDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/
# XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
# hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7
# M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3K
# Ni1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
# 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF80
# 3RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQc
# NIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahha
# YQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkL
# iWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV
# 2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIG
# CSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUp
# zxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
# MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYI
# KwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
# MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186a
# GMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1
# OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYA
# A7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
# aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6L
# GYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3m
# Sj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
# SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxko
# JLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFm
# PWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC482
# 2rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC0jCC
# AjsCAQEwgfyhgdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNv
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGODdBLUUzNzQtRDdCOTElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# vJqwk/xnycgV5Gdy5b4IwE/TWuOggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOYxQvEwIhgPMjAyMjA1MjAwMjI4
# MDFaGA8yMDIyMDUyMTAyMjgwMVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5jFC
# 8QIBADAKAgEAAgIeUAIB/zAHAgEAAgIQ5TAKAgUA5jKUcQIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBBQUAA4GBAEpSHXSwGQ+5eB/hRFgFjxVWZB4R66UITZg/0uBoVjno
# 9LNmQRRBQcNNcL7gXoeDGf6jUgQ4RbpMRBty8Xod4CmEE+9DG0bMqObLUH3K+xWX
# Nk48kgwkTTGW5e5aNFlCR8kAmIJGf/rLUd9y9k0Zj2/CEsvQw1sSniAmS7sUQZiL
# MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAGuqgtcszSllRoAAQAAAa4wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgBcdWARlQaJ3JLib04DrE
# bCHyjWOKyhjksliYWrWUtY0wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBJ
# KB0+uIzDWqHun09mqTU8uOg6tew0yu1uQ0iU/FJvaDCBmDCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABrqoLXLM0pZUaAAEAAAGuMCIEICUB
# +5Fn2lDmk7zupYipMP/l6m3Rusudg8czbMBe2TQDMA0GCSqGSIb3DQEBCwUABIIC
# AHy9xvN0OVvuZLyJkRPigP8q4Mu0b/yJM+2ZKX+cVnJzCr/CHzYN+7SXeye+m2Yn
# SzCqpFWuk8PSbPOaxW6a9HnSNt8J0kLz13FK0kKFF5vjKOg7c/9aRnJnLlPn2coo
# MKXQUJ0iKFNkajUBrp5DzgL+9JjPSkimb1hIbyr2hcU8G5gBaNkuN9UWzSk3aogG
# HxL/VN8ssZwEfOjjxrs7YXVb9kRazoLR02Ge5EOihVSxri6M38+/5HtirzWX0VVu
# mytYfFokxj+FaKHaLkJFY3y4iYXSa0lqz9PzvBw7ynmT2t4BRz55TCGlK5sA6WSY
# 1qZBcbotMKAqLYJqnIv0dPm32LfI5M/GzJ6m55uIeDbKKPUq63mrv1EXwm5mtdhm
# 1sOFyPTq0W9yt2vf7wSEd6kck/pmJ3osVztnIiBR4Roccxp7bWUJpgMQO2MuWBKk
# 7qcqSkpyhQHdVQoBlKjcrYSj42sHI7luzOLbsGVCcNYrOlK4BtL2oMW/YN41gDu8
# AWOCfNOJZJMU7lucM/IoDh6TejK2AWZ/nVMSipQS/QoitJVCJL0RHoYDK6iR8zDc
# OyxEDaem0dXGmClmR2lGSbArN1x3CdIlrYj8gKErZ1s0rucMkJqqNgk4eUhVoP/O
# hNNwb6v5kmx4SzpsdYONdbVpo6sgleXR5E8RV9/aiy2x
# SIG # End signature block
