<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2017 v5.4.142
	 Created on:   	04.08.2017 19:53
	 Created by:   	Mieszko Ślusarczyk
	 Filename:     	SCCM_ClientTools
	 Version:		1.0
	===========================================================================
	Bits and pieces taken from:
	http://blog.tyang.org/2011/08/05/powershell-function-get-alldomains-in-a-forest/
	https://blog.tyang.org/2012/02/16/powershell-script-get-sccm-management-point-server-name-from-ad/
	http://www.powershellmagazine.com/2013/04/23/pstip-get-the-ad-site-name-of-a-computer/
	.DESCRIPTION
		SCCM Client and SCCM PFE Agent tools.
#>
#region SMS Client Assignment Tools

#region Get-AllDomains
Function Get-AllDomains
{
	$Root = [ADSI]"LDAP://RootDSE"
	$oForestConfig = $Root.Get("configurationNamingContext")
	$oSearchRoot = [ADSI]("LDAP://CN=Partitions," + $oForestConfig)
	$AdSearcher = [adsisearcher]"(&(objectcategory=crossref)(netbiosname=*))"
	$AdSearcher.SearchRoot = $oSearchRoot
	$domains = $AdSearcher.FindAll()
	return $domains
}#endregion Get-AllDomains

#region Get-ADSite
function Get-ADSite
{
	param
	(
		$ComputerName = $env:COMPUTERNAME
	)
	Try
	{
		Write-Verbose "Info: trying to extract site code using System.DirectoryServices.ActiveDirectory.ActiveDirectorySite"
		$ADSite = ([System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite()).Name
	}
	Catch
	{
		Write-Verbose "Warning: failed to extract site code using System.DirectoryServices.ActiveDirectory.ActiveDirectorySite, trying nltest"
		If (!($ComputerName))
		{
			Write-Verbose "Error: Computer Name not passed"
		}
		$site = nltest /server:$ComputerName /dsgetsite 2>$null
		if ($LASTEXITCODE -eq 0) { $ADSite = $site[0] }
	}
	If ($ADSite)
	{
		Write-Verbose "Info: AD Site Name is $ADSite" 
	}
	Else
	{
		Write-Verbose "Error: Failed to find AD Site Name"
	}
	$ADSite
}#endregion Get-ADSite

#region Get-ADSiteCode
function Get-ADSiteCode
{
	param
	(
		$ADSite
	)
	
	
	If (!($ADSite))
	{
		$ADSite = Get-ADSite
	}
	Write-Verbose "ADSiteName $ADSite"
	try
	{
		$ADSiteCode = ($ADSite.split('-'))[1]
		Write-Verbose "AD Site Code $ADSiteCode"
	}
	catch
	{
	}
	Return $ADSiteCode
}#endregion Get-ADSiteCode

#region Get-SMSSiteCode
Function Get-SMSSiteCode
{
	param
	(
		[ValidateSet('AD','WMI')]
		[string]$Source = "AD",
		[bool]$Primary = $true
	)
	
	If ($Source -eq "AD")
	{
		If ($Primary -eq $true)
		{
			$SMSSiteCode = Get-SMSSiteCode -Source AD -Primary $false
			If ($SMSSiteCode)
			{
				Try
				{
					Write-Debug "Debug:Looking for $SMSSiteCode in $($Domain.Properties.ncname[0])"
					$ADSysMgmtContainer = [ADSI]("LDAP://CN=System Management,CN=System," + "$($Domain.Properties.ncname[0])")
					$AdSearcher = [adsisearcher]"(&(mSSMSSiteCode=$SMSSiteCode)(ObjectClass=mSSMSSite))"
					$AdSearcher.SearchRoot = $ADSysMgmtContainer
					$CMSiteFromAD = $AdSearcher.FindONE()
					$SMSPrimarySiteCode = $CMSiteFromAD.Properties.mssmsassignmentsitecode
					If ($SMSPrimarySiteCode)
					{
						Write-Verbose "Success: Found SCCM primary site code in AD $SMSPrimarySiteCode"
						$SMSSiteCode = $SMSPrimarySiteCode
					}
					Else
					{
						Write-Verbose "Error: Could not find SCCM primary site code"
					}
				}
				Catch
				{
					Write-Verbose "Error: Failed to find SCCM primary site code"
				}
			}
			Else
			{
				Write-Verbose "Error: Get-SMSSiteCode did not return SMSSiteCode"
			}
			
			Return $SMSSiteCode
		}
		ElseIf ($Primary -eq $false)
		{
			$domains = Get-AllDomains
			$ADSite = Get-ADSite
			Foreach ($script:domain in $domains)
			{
				Try
				{
					Write-Verbose "Looking for $ADSite in $($Domain.Properties.ncname[0])"
					$ADSysMgmtContainer = [ADSI]("LDAP://CN=System Management,CN=System," + "$($Domain.Properties.ncname[0])")
					$AdSearcher = [adsisearcher]"(&(mSSMSRoamingBoundaries=$ADSite)(ObjectClass=mSSMSSite))"
					$AdSearcher.SearchRoot = $ADSysMgmtContainer
					$CMSiteFromAD = $AdSearcher.FindONE()
					$SMSSiteCode = $CMSiteFromAD.Properties.mssmssitecode
					If ($SMSSiteCode)
					{
						Write-Verbose "Success: Found SCCM site code $SMSSiteCode"
						Break
					}
				}
				Catch { }
			}
			Return $SMSSiteCode
		}
	}
	ElseIf ($Source -eq "WMI")
	{
		If ($Primary -eq $true)
		{
			Try
			{
				Write-Verbose "Info: Trying to get primary site code assignment from WMI"
				$SMSPrimarySiteCode = ([wmiclass]"ROOT\ccm:SMS_Client").GetAssignedSite().sSiteCode
				If ($SMSPrimarySiteCode)
				{
					Write-Verbose "Success: Found SCCM primary site code in WMI $SMSPrimarySiteCode"
					$SMSSiteCode = $SMSPrimarySiteCode
				}
				Else
				{
					Write-Verbose "Error: Failed to get primary site code assignment from WMI"
				}
			}
			Catch
			{
				Write-Verbose "Error: Failed to get primary site code assignment from WMI"
			}
			Return $SMSSiteCode
		}
		ElseIf ($Primary -eq $false)
		{
			Try
			{
				Write-Verbose "Info: Trying to get site code assignment from WMI"
				$SMSSiteCode = Get-WmiObject -Namespace "ROOT\ccm" -Class "SMS_MPProxyInformation" -Property SiteCode | select -ExpandProperty SiteCode
				If ($SMSSiteCode)
				{
					Write-Verbose "Success: Found SCCM site code in WMI $SMSSiteCode"
				}
			}
			Catch
			{
				Write-Verbose "Error: Failed to get primary site code assignment from WMI"
			}
		}
	}
	
	
	If ($Primary -eq $true)
	{
		$SMSSiteCode = $SMSPrimarySiteCode
	}
}#endregion Get-SMSSiteCode

#region Get-SMSMP
Function Get-SMSMP
{
	param
	(
		[ValidateSet('AD', 'WMI')]
		[string]$Source = "AD",
		[bool]$Primary = $true
	)
	If ($Source -eq "AD")
	{
		If ($Primary -eq $true)
		{
			$SMSSiteCode = Get-SMSSiteCode -Source AD -Primary $true
			[string]$SMSMPType = "Primary Site Management Point"
		}
		ElseIf ($Primary -eq $false)
		{
			$SMSSiteCode = Get-SMSSiteCode -Source AD -Primary $false
			[string]$SMSMPType = "Management Point"
		}
		
		If ($SMSSiteCode)
		{
			Write-Verbose "Info: Trying to find SCCM $SMSMPType in AD"
			Try
			{
				$ADSysMgmtContainer = [ADSI]("LDAP://CN=System Management,CN=System," + "$($Domain.Properties.ncname[0])")
				$AdSearcher = [adsisearcher]"(&(Name=SMS-MP-$SMSSiteCode-*)(objectClass=mSSMSManagementPoint))"
				$AdSearcher.SearchRoot = $ADSysMgmtContainer
				$CMManagementPointFromAD = $AdSearcher.FindONE()
				$MP = $CMManagementPointFromAD.Properties.mssmsmpname[0]
				If ($MP)
				{
					Write-Verbose "Success: Found SCCM $SMSMPType $MP in AD"
				}
				Else
				{
					Write-Verbose "Error: Failed to find SCCM $SMSMPType in AD"
				}
			}
			Catch
			{
				Write-Verbose "Error: Failed to find SCCM $SMSMPType in AD"
			}
		}
		Else
		{
			Write-Verbose "Error: Get-SMSSiteCode did not return SMSPrimarySiteCode"
		}
	}
	ElseIf ($Source -eq "WMI")
	{
		If ($Primary -eq $true)
		{
			[string]$SMSMPType = "Primary Site Management Point"
		}
		ElseIf ($Primary -eq $false)
		{
			[string]$SMSMPType = "Management Point"
		}
		Write-Verbose "Info: Trying to find SCCM $SMSMPType in WMI"
		
		Try
		{
			If ($Primary -eq $true)
			{
				$MP = Get-WmiObject -Namespace "ROOT\ccm" -Class "SMS_LookupMP" -Property Name | select -ExpandProperty Name
			}
			ElseIf ($Primary -eq $false)
			{
				$MP = Get-WmiObject -Namespace "ROOT\ccm" -Class "SMS_LocalMP" -Property Name | select -ExpandProperty Name
			}
			If ($MP)
			{
				Write-Verbose "Scuccess: SCCM $SMSMPType in WMI is $MP"
			}
			Else
			{
				Write-Verbose "Info: Failed to find SCCM $SMSMPType in WMI"
			}
		}
		Catch
		{
			Write-Verbose "Info: Failed to find SCCM $SMSMPType in WMI"
		}
	}

	Return $MP
}#endregion Get-SMSMP

#region Check-SMSAssignedSite
function Check-SMSAssignedSite
{
	Write-Verbose "Info: Checking SCCM client assignment"
	[string]$SMSSiteCodeWMI = Get-SMSSiteCode -Source WMI -Primary $true
	If ($SMSSiteCodeWMI)
	{
		[string]$SMSSiteCodeAD = Get-SMSSiteCode -Source AD -Primary $true
		If ("$SMSSiteCodeAD" -eq "$SMSSiteCodeWMI")
		{
			Write-Verbose "Info: SCCM client assignment is up to date ($SMSSiteCodeWMI)"
		}
		Else
		{
			Write-Verbose "Warning: SCCM Site Code in WMI: $SMSSiteCodeWMI in AD: $SMSSiteCodeAD "
			Write-Verbose "Warning: SCCM client assignment is NOT up to date, trying to automatically set it"
			Set-SMSSiteCode
		}
	}
	Else
	{
		Write-Verbose "Warning: SCCM client couldn't read SCCM site assignment, trying to automatically set it"
		Set-SMSSiteCode
	}
}#endregion Check-SMSAssignedSite

#endregion SMS Client Assignment Tools

#region PFE Agent tools

#region Get-PFESiteAssignment
Function Get-PFESiteAssignment
{
	<#
			Created on:   	05.08.2017 00:43
			Created by:   	Mieszko Ślusarczyk
			Version:		1.0
    .SYNOPSIS
    Get SCCM PFE Remediation Agent Server name.
    
    .DESCRIPTION
	The script will read the primary SCCM site currently assigned to SCCM PFE Remediation Agent from registry and display it's FQDN

    
    .EXAMPLE
    Get-PFESiteAssignment

    .DEPENDENT FUNCTIONS
    

    #>
	If (Test-Path "HKLM:\SOFTWARE\Microsoft\Microsoft PFE Remediation for Configuration Manager")
	{
		Try
		{
			$PFEServer = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft PFE Remediation for Configuration Manager").PrimarySiteName
			If ($PFEServer)
			{
				If ($global:blnDebug) { Write-Verbose "Info: PFE server name is $PFEServer" }
			}
			Else
			{
				Write-Verbose "Error: Could not get PFE server name"
			}
		}
		Catch
		{
			Write-Verbose "Error: Could not get PFE server name"
		}
	}
	Else
	{
		Write-Verbose "Error: `"HKLM:\SOFTWARE\Microsoft\Microsoft PFE Remediation for Configuration Manager`" does not exist"
	}
	Return $PFEServer
}#endregion Get-PFESiteAssignment

#region Set-PFESiteAssignment
Function Set-PFESiteAssignment
{
	<#
		#	Created on:   	08.08.2017 14:00
		#	Created by:   	Mieszko Ślusarczyk
    .SYNOPSIS
    Set SCCM PFE Remediation Agent Server name.
    
    .DESCRIPTION
	The script will assign PFE Remediation Agent with SCCM primary site and display it's FQDN

    
    .EXAMPLE
    Set-PFESiteAssignment

    .DEPENDENT FUNCTIONS
    

    #>
	$PrimarySiteServer = Get-SMSMP -Source AD -Primary $true
	If ($PrimarySiteServer)
	{
		If (Test-Path "HKLM:\SOFTWARE\Microsoft\Microsoft PFE Remediation for Configuration Manager")
		{
			Try
			{
				
				Write-Verbose "Info: Setting PFE server name to $PrimarySiteServer"
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft PFE Remediation for Configuration Manager" -Name PrimarySiteName -Value "$PrimarySiteServer"
				Try
				{
					Write-Verbose "Info: PFE server name changed, restarting PFERemediation service"
					Restart-Service PFERemediation
				}
				Catch
				{
					Write-Verbose "Error: Failed restart PFERemediation service"
				}
			}
			Catch
			{
				Write-Verbose "Error: Failed to set PFE server name to $PrimarySiteServer"
			}
		}
		Else
		{
			Write-Verbose "Error: `"HKLM:\SOFTWARE\Microsoft\Microsoft PFE Remediation for Configuration Manager`" does not exist."
		}
	}
	Else
	{
		Write-Verbose "Error: No Primary Site Server FQDN detected"
	}
}#endregion Set-PFESiteAssignment

#region Check-PFEAssignedSite
function Check-PFEAssignedSite
{
	Write-Verbose "Info: Checking PFE agent assignment"
	[string]$PFESiteAssignment = Get-PFESiteAssignment
	[string]$SMSMP = Get-SMSMP -Source AD -Primary $true
	If ($PFESiteAssignment)
	{
		If ($PFESiteAssignment -eq $SMSMP)
		{
			Write-Verbose "Info: PFE agent assignment is up to date ($PFESiteAssignment)"
		}
		Else
		{
			Write-Verbose "Warning: PFE agent assignment is: $PFESiteAssignment, SCCM Primary Management point is $SMSMP"
			Write-Verbose "Warning: PFE agent assignment is NOT up to date trying to automatically set it"
			Set-PFESiteAssignment
		}
	}
	Else
	{
		Write-Verbose "Warning: PFE agent couldn't read site assignment, trying to automatically set it"
		Set-PFESiteAssignment
	}
}#endregion Check-PFEAssignedSite

#region Restart-PFEAgent
function Restart-PFEAgent
{
	Stop-Service PFERemediation
	Start-Service PFERemediation
}#endregion Restart-PFEAgent

#endregion PFE Agent tools