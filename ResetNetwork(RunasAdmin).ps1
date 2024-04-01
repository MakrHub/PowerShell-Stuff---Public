 #flush dns and reset network, requires computer restart to finish
"ipconfig /release && ipconfig /flushdns && ipconfig /renew && ipconfig /registerdns && netsh int ip reset && netsh winsock reset" | cmd 
Write-Host "DNS flushed successfully, DHCP renewed, and Winsock reset will occur after a computer restart" -ForegroundColor Green
Read-Host "Press Enter to restart now"
Restart-Computer