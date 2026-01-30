# Disable screen blanking
xset s off
xset s noblank
xset -dpms

# Hide cursor after 1 second
unclutter -idle 1 &

# Wait for Home Assistant to be ready
echo "Waiting for Home Assistant..."
while ! curl -s -o /dev/null -w "%{http_code}" "{{KIOSK_URL}}" | grep -q "200\|401"; do
    sleep 5
done
echo "Home Assistant ready"

# Start Firefox in kiosk mode
exec firefox-esr --kiosk "{{KIOSK_URL}}"
