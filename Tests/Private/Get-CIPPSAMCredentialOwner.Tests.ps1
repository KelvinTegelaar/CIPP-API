# Owner classification drives which CIPP-SAM credentials the credentials page lets an admin revoke.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CIPPSAMCredentialOwner.ps1')
}

Describe 'Get-CIPPSAMCredentialOwner' {
    It 'classifies <Case>' -ForEach @(
        @{ Case = 'the tracked secret as thisInstance'; Params = @{ KeyId = 'k1'; DisplayName = 'UpdateTokens'; OwnSecretKeyId = 'k1' }; Expected = 'thisInstance' }
        @{ Case = 'the stored certificate as thisInstance'; Params = @{ KeyId = 'c1'; Type = 'Certificate'; DisplayName = 'CIPP-SAM Certificate (a)'; Thumbprint = 'AB'; OwnThumbprint = 'AB' }; Expected = 'thisInstance' }
        @{ Case = 'another CIPP secret as otherCipp when tracking is on'; Params = @{ KeyId = 'k2'; DisplayName = 'CIPPInstall'; OwnSecretKeyId = 'k1' }; Expected = 'otherCipp' }
        @{ Case = 'a CIPP-prefixed secret as otherCipp when tracking is on'; Params = @{ KeyId = 'k2'; DisplayName = 'CIPP-Other'; OwnSecretKeyId = 'k1' }; Expected = 'otherCipp' }
        @{ Case = 'a CIPP secret as unknown before tracking existed'; Params = @{ KeyId = 'k2'; DisplayName = 'UpdateTokens'; OwnSecretKeyId = '' }; Expected = 'unknown' }
        @{ Case = 'another CIPP certificate as otherCipp without a tracked secret'; Params = @{ KeyId = 'c2'; Type = 'Certificate'; DisplayName = 'CIPP-SAM Certificate (b)'; Thumbprint = 'CD'; OwnThumbprint = 'AB' }; Expected = 'otherCipp' }
        @{ Case = 'a non-CIPP secret as external'; Params = @{ KeyId = 'k3'; DisplayName = 'Rewst'; OwnSecretKeyId = '' }; Expected = 'external' }
        @{ Case = 'a non-CIPP certificate as external'; Params = @{ KeyId = 'c3'; Type = 'Certificate'; DisplayName = 'Vendor cert'; Thumbprint = 'EF'; OwnThumbprint = 'AB' }; Expected = 'external' }
        @{ Case = 'a secret whose keyId equals the cert thumbprint without crossing types'; Params = @{ KeyId = 'AB'; DisplayName = 'Rewst'; OwnThumbprint = 'AB' }; Expected = 'external' }
    ) {
        $Params = $_.Params
        Get-CIPPSAMCredentialOwner @Params | Should -Be $_.Expected
    }
}
