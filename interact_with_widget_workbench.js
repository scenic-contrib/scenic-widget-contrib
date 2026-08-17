#!/usr/bin/env node

const net = require('net');

function sendCommand(command) {
  return new Promise((resolve, reject) => {
    const client = new net.Socket();
    let responseData = '';
    let helloReceived = false;

    client.connect(9999, 'localhost', () => {
      console.log('Connected to scenic_mcp server');
      // Always send hello first
      client.write('hello\n');
    });

    client.on('data', (data) => {
      responseData += data.toString();
      
      if (!helloReceived && responseData.includes('Hello from Scenic MCP Server')) {
        helloReceived = true;
        responseData = ''; // Clear the hello response
        
        // Now send the actual command
        const cmdStr = JSON.stringify(command) + '\n';
        console.log('Sending command:', cmdStr);
        client.write(cmdStr);
      } else if (helloReceived) {
        // We have the response to our command
        client.destroy();
        try {
          const response = JSON.parse(responseData.trim());
          resolve(response);
        } catch (e) {
          resolve(responseData.trim());
        }
      }
    });

    client.on('error', (err) => {
      reject(err);
    });

    client.on('close', () => {
      if (responseData && helloReceived) {
        try {
          const response = JSON.parse(responseData.trim());
          resolve(response);
        } catch (e) {
          resolve(responseData.trim());
        }
      }
    });

    setTimeout(() => {
      client.destroy();
      reject(new Error('Connection timeout'));
    }, 5000);
  });
}

async function main() {
  try {
    // First inspect the viewport
    console.log('\n=== Inspecting Viewport ===');
    const viewportData = await sendCommand({ action: 'inspect_viewport' });
    console.log('Viewport data:', JSON.stringify(viewportData, null, 2));
    
    // Take a screenshot before clicking
    console.log('\n=== Taking screenshot before click ===');
    const screenshotBefore = await sendCommand({ 
      action: 'take_screenshot',
      filename: 'before_load_component_click.png'
    });
    console.log('Screenshot saved:', screenshotBefore);
    
    // Click on the "Load Component" button (around x=1100, y=400)
    console.log('\n=== Clicking "Load Component" button ===');
    const clickResult = await sendCommand({ 
      action: 'send_mouse_click',
      x: 1100,
      y: 400
    });
    console.log('Click result:', clickResult);
    
    // Wait a moment for any UI updates
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Take a screenshot after clicking
    console.log('\n=== Taking screenshot after click ===');
    const screenshotAfter = await sendCommand({ 
      action: 'take_screenshot',
      filename: 'after_load_component_click.png'
    });
    console.log('Screenshot saved:', screenshotAfter);
    
    // Inspect viewport again to see any changes
    console.log('\n=== Inspecting Viewport after click ===');
    const viewportDataAfter = await sendCommand({ action: 'inspect_viewport' });
    console.log('Viewport data after click:', JSON.stringify(viewportDataAfter, null, 2));
    
  } catch (error) {
    console.error('Error:', error);
  }
}

main();