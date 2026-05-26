/**
 * E-Commerce Microservices Frontend Application
 * Handles API calls, authentication flows, shopping cart, and diagnostics.
 */

// API Endpoints
const API_URLS = {
    user: 'http://localhost:8001',
    product: 'http://localhost:8002',
    order: 'http://localhost:8003',
    payment: 'http://localhost:8004',
    notification: 'http://localhost:8005'
};

// Application State
const state = {
    products: [],
    orders: [],
    notifications: [],
    activeUser: null,
    cart: [], // Array of { product: {}, quantity: 1 }
    activeTab: 'store'
};

// Initialize Application
document.addEventListener('DOMContentLoaded', async () => {
    initTabNavigation();
    initCartPanel();
    initAuthForms();
    
    // Check for cached user session (Auto-Login)
    const cachedUser = localStorage.getItem('apex_user');
    if (cachedUser) {
        try {
            state.activeUser = JSON.parse(cachedUser);
            showMainDashboard();
        } catch (e) {
            localStorage.removeItem('apex_user');
            showAuthPortal();
        }
    } else {
        showAuthPortal();
    }

    // Global Diagnostics Ping on load
    await pingAllServices();

    // Event listeners
    document.getElementById('refreshOrdersBtn').addEventListener('click', loadOrders);
    document.getElementById('refreshNotificationsBtn').addEventListener('click', loadNotifications);
    document.getElementById('pingHealthBtn').addEventListener('click', pingAllServices);
    document.getElementById('logoutBtn').addEventListener('click', handleLogout);
    
    // Setup category filters
    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            renderProducts(e.target.dataset.category);
        });
    });
});

// ── Authentication UI & State Controllers ──────────────────────────────────
function showAuthPortal() {
    document.getElementById('authPortalOverlay').style.display = 'flex';
    document.getElementById('appMainContainer').style.display = 'none';
    document.getElementById('sidebarProfileBox').style.display = 'none';
    switchAuthView('login');
}

function showMainDashboard() {
    document.getElementById('authPortalOverlay').style.display = 'none';
    document.getElementById('appMainContainer').style.display = 'flex';
    
    // Populate Sidebar Profile Badge
    document.getElementById('activeUserName').textContent = state.activeUser.full_name || state.activeUser.username;
    document.getElementById('activeUserEmail').textContent = state.activeUser.email;
    document.getElementById('sidebarProfileBox').style.display = 'block';

    // Fetch account-level catalog & transactions data
    loadProducts();
    loadOrders();
    loadNotifications();
}

// Global scope view switcher for inline index.html onclick triggers
window.switchAuthView = function(view) {
    const views = ['Login', 'Register', 'Forgot'];
    views.forEach(v => {
        document.getElementById(`authView${v}`).style.display = 'none';
    });
    
    // Show target view
    const target = view.charAt(0).toUpperCase() + view.slice(1);
    const viewEl = document.getElementById(`authView${target}`);
    if (viewEl) {
        viewEl.style.display = 'flex';
    }
};

function initAuthForms() {
    // A. Login Form Handler
    document.getElementById('loginForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const usernameOrEmail = document.getElementById('loginUsername').value.trim();
        const password = document.getElementById('loginPassword').value;
        const submitBtn = document.getElementById('loginSubmitBtn');

        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span>Authenticating...</span> <i class="fa-solid fa-spinner fa-spin"></i>';

        try {
            const res = await fetch(`${API_URLS.user}/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username_or_email: usernameOrEmail, password })
            });

            if (res.status === 401) {
                showToast('Invalid username/email or password', 'error');
                return;
            }
            if (!res.ok) throw new Error('Authentication failed');
            
            const userData = await res.json();
            
            // Success Auth state
            state.activeUser = userData;
            localStorage.setItem('apex_user', JSON.stringify(userData));
            
            showToast(`Welcome back, ${userData.username}!`, 'success');
            showMainDashboard();

            // Clear inputs
            document.getElementById('loginUsername').value = '';
            document.getElementById('loginPassword').value = '';
        } catch (err) {
            console.error(err);
            showToast('Unable to connect to User Service database', 'error');
        } finally {
            submitBtn.disabled = false;
            submitBtn.innerHTML = '<span>Log In</span> <i class="fa-solid fa-right-to-bracket"></i>';
        }
    });

    // B. Register/Create User Form Handler
    document.getElementById('registerForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const email = document.getElementById('regEmail').value.trim();
        const username = document.getElementById('regUsername').value.trim();
        const fullName = document.getElementById('regFullName').value.trim();
        const password = document.getElementById('regPassword').value;
        const submitBtn = document.getElementById('registerSubmitBtn');

        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span>Creating Account...</span> <i class="fa-solid fa-spinner fa-spin"></i>';

        try {
            const res = await fetch(`${API_URLS.user}/`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, username, full_name: fullName, password })
            });

            if (res.status === 409) {
                showToast('Username or Email already registered', 'error');
                return;
            }
            if (!res.ok) throw new Error('Registration failed');
            
            showToast('Account successfully created! Please log in.', 'success');
            
            // Prefill login and switch back
            document.getElementById('loginUsername').value = username;
            switchAuthView('login');

            // Clear form
            document.getElementById('regEmail').value = '';
            document.getElementById('regUsername').value = '';
            document.getElementById('regFullName').value = '';
            document.getElementById('regPassword').value = '';
        } catch (err) {
            console.error(err);
            showToast('Database error during account registration', 'error');
        } finally {
            submitBtn.disabled = false;
            submitBtn.innerHTML = '<span>Register</span> <i class="fa-solid fa-user-plus"></i>';
        }
    });

    // C. Forgot Password Form Handler
    document.getElementById('forgotForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const email = document.getElementById('forgotEmail').value.trim();
        const submitBtn = document.getElementById('forgotSubmitBtn');

        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span>Dispatching Event...</span> <i class="fa-solid fa-spinner fa-spin"></i>';

        try {
            const res = await fetch(`${API_URLS.user}/forgot-password`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email })
            });

            if (res.status === 404) {
                showToast('User email not found in database', 'error');
                return;
            }
            if (!res.ok) throw new Error('Reset request failed');
            
            showToast('Instructions dispatched via Notification microservice!', 'success');
            switchAuthView('login');
            
            document.getElementById('forgotEmail').value = '';
        } catch (err) {
            console.error(err);
            showToast('Unable to queue password reset trigger', 'error');
        } finally {
            submitBtn.disabled = false;
            submitBtn.innerHTML = '<span>Send Instructions</span> <i class="fa-solid fa-paper-plane"></i>';
        }
    });
}

function handleLogout() {
    localStorage.removeItem('apex_user');
    state.activeUser = null;
    state.cart = [];
    updateCartUI();
    showToast('Logged out of active storefront session', 'info');
    showAuthPortal();
}

// ── Tab Management ─────────────────────────────────────────────────────────
function initTabNavigation() {
    const navItems = document.querySelectorAll('.nav-item');
    const tabPanes = document.querySelectorAll('.tab-pane');

    navItems.forEach(item => {
        item.addEventListener('click', () => {
            const targetTab = item.dataset.tab;
            state.activeTab = targetTab;

            // Toggle Navigation States
            navItems.forEach(nav => nav.classList.remove('active'));
            item.classList.add('active');

            // Toggle Panes Visibility
            tabPanes.forEach(pane => pane.classList.remove('active'));
            document.getElementById(`tab-${targetTab}`).classList.add('active');

            // Update Header titles
            const titleElement = document.getElementById('currentTabTitle');
            const subElement = document.getElementById('currentTabSub');
            
            if (targetTab === 'store') {
                titleElement.textContent = 'Storefront';
                subElement.textContent = 'Browse and purchase premium pre-seeded electronic catalog items.';
            } else if (targetTab === 'orders') {
                titleElement.textContent = 'Transactions Manager';
                subElement.textContent = 'Live status updates of orders and direct triggers to microservice databases.';
                loadOrders();
            } else if (targetTab === 'notifications') {
                titleElement.textContent = 'Notification Dispatcher';
                subElement.textContent = 'Real-time record of all SMS, emails, and alerts sent by background tasks.';
                loadNotifications();
            } else if (targetTab === 'status') {
                titleElement.textContent = 'API Cluster Gateway';
                subElement.textContent = 'Diagnostic connection metrics for backend FastAPI microservices.';
                pingAllServices();
            }
        });
    });
}

// ── Shopping Cart Logic ───────────────────────────────────────────────────
function initCartPanel() {
    const cartTrigger = document.getElementById('cartTrigger');
    const cartClose = document.getElementById('cartClose');
    const cartOverlay = document.getElementById('cartOverlay');
    const cartPanel = document.getElementById('cartPanel');
    const checkoutBtn = document.getElementById('checkoutBtn');

    const toggleCart = () => {
        cartPanel.classList.toggle('active');
        cartOverlay.classList.toggle('active');
    };

    cartTrigger.addEventListener('click', toggleCart);
    cartClose.addEventListener('click', toggleCart);
    cartOverlay.addEventListener('click', toggleCart);
    checkoutBtn.addEventListener('click', handleCheckout);
}

function addToCart(productId) {
    const product = state.products.find(p => p.id === productId);
    if (!product) return;

    const existingItem = state.cart.find(item => item.product.id === productId);
    if (existingItem) {
        existingItem.quantity += 1;
    } else {
        state.cart.push({ product, quantity: 1 });
    }

    showToast(`Added ${product.name} to cart`, 'info');
    updateCartUI();
}

function removeFromCart(productId) {
    state.cart = state.cart.filter(item => item.product.id !== productId);
    updateCartUI();
}

function updateCartUI() {
    const cartItemsList = document.getElementById('cartItemsList');
    const cartCountBadge = document.getElementById('cartCountBadge');
    const cartSubtotal = document.getElementById('cartSubtotal');
    const cartTotal = document.getElementById('cartTotal');
    const checkoutBtn = document.getElementById('checkoutBtn');

    // Update Badge
    const totalCount = state.cart.reduce((sum, item) => sum + item.quantity, 0);
    cartCountBadge.textContent = totalCount;

    if (state.cart.length === 0) {
        cartItemsList.innerHTML = `
            <div class="cart-empty-message">
                <i class="fa-solid fa-cart-flatbed empty-icon"></i>
                <p>Your cart is empty.</p>
            </div>
        `;
        cartSubtotal.textContent = '$0.00';
        cartTotal.textContent = '$0.00';
        checkoutBtn.disabled = true;
        return;
    }

    // Render Items
    let subtotal = 0;
    cartItemsList.innerHTML = state.cart.map(item => {
        const itemTotal = parseFloat(item.product.price) * item.quantity;
        subtotal += itemTotal;
        return `
            <div class="cart-item">
                <div class="cart-item-info">
                    <div class="cart-item-name">${item.product.name}</div>
                    <div class="cart-item-price">$${parseFloat(item.product.price).toFixed(2)}</div>
                    <div class="cart-item-qty">Quantity: ${item.quantity}</div>
                </div>
                <button class="cart-item-remove" onclick="removeFromCart(${item.product.id})">
                    <i class="fa-solid fa-trash-can"></i>
                </button>
            </div>
        `;
    }).join('');

    cartSubtotal.textContent = `$${subtotal.toFixed(2)}`;
    cartTotal.textContent = `$${subtotal.toFixed(2)}`;
    checkoutBtn.disabled = false;
}

// ── API Fetch Calls ────────────────────────────────────────────────────────

// 1. Fetch pre-seeded product catalog
async function loadProducts() {
    const grid = document.getElementById('productGrid');
    try {
        const res = await fetch(`${API_URLS.product}/`);
        if (!res.ok) throw new Error('Could not fetch products');
        const data = await res.json();
        state.products = data;
        renderProducts('all');
    } catch (err) {
        console.error(err);
        grid.innerHTML = `
            <div class="empty-state">
                <i class="fa-solid fa-circle-exclamation empty-icon" style="color: var(--danger)"></i>
                <h4>Could not connect to catalog</h4>
                <p>Ensure the Product Service microservice container is up and running on port 8002.</p>
            </div>
        `;
    }
}

function renderProducts(category) {
    const grid = document.getElementById('productGrid');
    const filtered = category === 'all' 
        ? state.products 
        : state.products.filter(p => p.category === category);

    if (filtered.length === 0) {
        grid.innerHTML = `
            <div class="empty-state">
                <i class="fa-solid fa-boxes-packing empty-icon"></i>
                <h4>No products found</h4>
                <p>No products exist under category "${category}".</p>
            </div>
        `;
        return;
    }

    grid.innerHTML = filtered.map(product => `
        <article class="product-card">
            <div class="product-img-box">
                <span class="product-cat-tag">${product.category}</span>
                <img class="product-img" src="${product.image_url || 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=400'}" alt="${product.name}">
            </div>
            <div class="product-info-box">
                <h4 class="product-title">${product.name}</h4>
                <p class="product-desc">${product.description || 'No description provided.'}</p>
                <div class="product-footer">
                    <div>
                        <div class="product-price">$${parseFloat(product.price).toFixed(2)}</div>
                        <div class="product-stock ${product.stock_quantity <= 10 ? 'low-stock' : ''}">Stock: ${product.stock_quantity} units</div>
                    </div>
                    <button class="btn btn-primary btn-icon-only" onclick="addToCart(${product.id})">
                        <i class="fa-solid fa-plus"></i>
                    </button>
                </div>
            </div>
        </article>
    `).join('');
}

// 2. Checkout and create order
async function handleCheckout() {
    if (!state.activeUser || state.cart.length === 0) return;

    const checkoutBtn = document.getElementById('checkoutBtn');
    checkoutBtn.disabled = true;
    checkoutBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Submitting...';

    const orderPayload = {
        user_id: state.activeUser.id,
        items: state.cart.map(item => ({
            product_id: item.product.id,
            quantity: item.quantity,
            price: parseFloat(item.product.price)
        })),
        shipping_address: {
            street: '100 Terminal Drive',
            city: 'Silicon Valley',
            country: 'USA'
        }
    };

    try {
        const res = await fetch(`${API_URLS.order}/`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(orderPayload)
        });

        if (!res.ok) throw new Error('Checkout request failed');
        const orderRes = await res.json();
        
        showToast(`Order #${orderRes.id} successfully created!`, 'success');
        
        // Trigger simulated order notifications
        sendOrderNotifications(orderRes);

        // Clear cart
        state.cart = [];
        updateCartUI();
        
        // Slide out cart
        document.getElementById('cartPanel').classList.remove('active');
        document.getElementById('cartOverlay').classList.remove('active');

        // Go to orders tab
        document.querySelector('[data-tab="orders"]').click();
    } catch (err) {
        console.error(err);
        showToast('Checkout failed. Is Order Service running?', 'error');
    } finally {
        checkoutBtn.disabled = false;
        checkoutBtn.innerHTML = '<i class="fa-solid fa-credit-card"></i> Proceed to Checkout';
    }
}

// Simulate triggering background notifications
async function sendOrderNotifications(order) {
    try {
        await fetch(`${API_URLS.notification}/`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                user_id: order.user_id,
                type: 'email',
                subject: `Order #${order.id} Placed`,
                message: `Thank you for your purchase! Your order total is $${parseFloat(order.total_amount).toFixed(2)}. We will send shipping updates soon.`,
                metadata: { order_id: order.id }
            })
        });
        loadNotifications();
    } catch (err) {
        console.warn('Failed to dispatch checkout notification', err);
    }
}

// 3. Fetch User Orders
async function loadOrders() {
    if (!state.activeUser) return;
    const container = document.getElementById('ordersContainer');
    
    try {
        const res = await fetch(`${API_URLS.order}/user/${state.activeUser.id}`);
        if (!res.ok) throw new Error('Failed to fetch orders');
        const data = await res.json();
        state.orders = data;

        if (data.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <i class="fa-solid fa-box-open empty-icon"></i>
                    <h4>No orders found</h4>
                    <p>Go to the Storefront and purchase products to populate this log.</p>
                </div>
            `;
            return;
        }

        container.innerHTML = data.map(order => {
            const formattedDate = new Date(order.created_at).toLocaleString();
            const itemsList = order.items.map(item => {
                const prod = state.products.find(p => p.id === item.product_id);
                const name = prod ? prod.name : `Product ID: ${item.product_id}`;
                return `
                    <div class="order-item-row">
                        <span class="order-item-desc">${name} (x${item.quantity})</span>
                        <span class="order-item-price">$${(parseFloat(item.price) * item.quantity).toFixed(2)}</span>
                    </div>
                `;
            }).join('');

            const isPending = order.status === 'pending';
            const actionButton = isPending
                ? `<button class="btn btn-primary" onclick="processPayment(${order.id}, ${parseFloat(order.total_amount)})"><i class="fa-solid fa-credit-card"></i> Pay Now</button>`
                : `<span style="font-size: 13px; color: var(--success); font-weight: 700;"><i class="fa-solid fa-circle-check"></i> Transaction Completed</span>`;

            return `
                <div class="order-card">
                    <div class="order-card-header">
                        <div>
                            <span class="order-id-badge">Order ID: #${order.id}</span>
                            <div class="order-date">${formattedDate}</div>
                        </div>
                        <span class="order-status-badge status-${order.status}">${order.status}</span>
                    </div>
                    <div class="order-card-body">
                        ${itemsList}
                    </div>
                    <div class="order-card-footer">
                        <div>
                            <span class="order-total-lbl">Total Paid</span>
                            <div class="order-total-price">$${parseFloat(order.total_amount).toFixed(2)}</div>
                        </div>
                        <div>
                            ${actionButton}
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    } catch (err) {
        console.error(err);
        container.innerHTML = `
            <div class="empty-state">
                <i class="fa-solid fa-triangle-exclamation empty-icon" style="color: var(--warning)"></i>
                <h4>Connection Error</h4>
                <p>Could not fetch user orders. Check if Order Service is online.</p>
            </div>
        `;
    }
}

// 4. Trigger Simulated Payments
async function processPayment(orderId, amount) {
    showToast(`Processing payment for Order #${orderId}...`, 'info');
    
    try {
        // Post payment details
        const payRes = await fetch(`${API_URLS.payment}/`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                order_id: orderId,
                user_id: state.activeUser.id,
                amount: amount,
                currency: 'USD',
                payment_method: 'digital_wallet'
            })
        });

        if (!payRes.ok) throw new Error('Payment processing failed');
        const payData = await payRes.json();

        // Patch Order Status to confirmed
        const patchRes = await fetch(`${API_URLS.order}/${orderId}/status?new_status=confirmed`, {
            method: 'PATCH'
        });
        if (!patchRes.ok) throw new Error('Order status update failed');

        showToast(`Payment processed successfully! Transaction ID: ${payData.payment_id}`, 'success');

        // Send email receipt
        await fetch(`${API_URLS.notification}/`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                user_id: state.activeUser.id,
                type: 'email',
                subject: `Receipt for Order #${orderId}`,
                message: `Hello ${state.activeUser.username}! We received your payment of $${amount.toFixed(2)} for order #${orderId}. Payment ID: ${payData.payment_id}. Your items are being packed for delivery.`,
                metadata: { payment_id: payData.payment_id }
            })
        });

        loadOrders();
        loadNotifications();
    } catch (err) {
        console.error(err);
        showToast('Payment processing failed. Is Payment Service running?', 'error');
    }
}

// 5. Fetch User Notification Log
async function loadNotifications() {
    if (!state.activeUser) return;
    const container = document.getElementById('notificationsList');

    try {
        const res = await fetch(`${API_URLS.notification}/user/${state.activeUser.id}`);
        if (!res.ok) throw new Error('Could not fetch notifications');
        const data = await res.json();

        if (data.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <i class="fa-solid fa-envelope-open empty-icon"></i>
                    <h4>No dispatch history</h4>
                    <p>Alert logs will appear here after orders are placed and payments completed.</p>
                </div>
            `;
            return;
        }

        container.innerHTML = data.map(n => {
            const formattedTime = new Date(n.created_at).toLocaleString();
            return `
                <div class="notify-item">
                    <div class="notify-icon notify-icon-${n.type}">
                        <i class="fa-solid ${n.type === 'email' ? 'fa-envelope-open-text' : 'fa-mobile-screen-button'}"></i>
                    </div>
                    <div class="notify-content">
                        <div class="notify-header-row">
                            <span class="notify-subject">${n.subject || 'System Notification'}</span>
                            <span class="notify-time">${formattedTime}</span>
                        </div>
                        <p class="notify-msg">${n.message}</p>
                        <span class="notify-status status-completed" style="font-size: 9px; padding: 2px 6px;">DISPATCHED</span>
                    </div>
                </div>
            `;
        }).join('');
    } catch (err) {
        console.error(err);
        container.innerHTML = `
            <div class="empty-state">
                <i class="fa-solid fa-envelope-circle-check empty-icon" style="color: var(--text-muted)"></i>
                <h4>Unable to sync events</h4>
                <p>Notification logs could not be synced. Verify status of Notification Service container.</p>
            </div>
        `;
    }
}

// ── System Health Diagnostics ──────────────────────────────────────────────

async function pingAllServices() {
    const services = ['user', 'product', 'order', 'payment', 'notification'];
    
    for (const service of services) {
        const card = document.getElementById(`status-${service}`);
        const badge = card.querySelector('.status-indicator-badge');
        const readinessEl = card.querySelector('.readiness-text');
        const versionEl = card.querySelector('.version-text');

        try {
            // Ping healthz
            const healthRes = await fetch(`${API_URLS[service]}/healthz`);
            if (!healthRes.ok) throw new Error('Unhealthy');
            const healthData = await healthRes.json();

            // Ping readyz
            const readyRes = await fetch(`${API_URLS[service]}/readyz`);
            let isReady = false;
            if (readyRes.ok) {
                const readyData = await readyRes.json();
                isReady = readyData.status === 'ready';
            }

            // Update DOM to Healthy
            badge.className = 'status-indicator-badge badge-online';
            badge.textContent = 'Healthy';
            readinessEl.innerHTML = isReady 
                ? '<span style="color: var(--success); font-weight: 700;">Connected to DB</span>' 
                : '<span style="color: var(--warning)">Connecting</span>';
            versionEl.textContent = healthData.version || '1.0.0';

        } catch (err) {
            // Update DOM to Offline
            badge.className = 'status-indicator-badge badge-offline';
            badge.textContent = 'Offline';
            readinessEl.innerHTML = '<span style="color: var(--danger)">No Connection</span>';
            versionEl.textContent = 'N/A';
        }
    }
}

// ── Helper Toast UI ────────────────────────────────────────────────────────
function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    
    let iconClass = 'fa-circle-info';
    if (type === 'success') iconClass = 'fa-circle-check';
    if (type === 'error') iconClass = 'fa-circle-xmark';

    toast.innerHTML = `
        <i class="fa-solid ${iconClass}"></i>
        <div>${message}</div>
    `;

    container.appendChild(toast);

    // Auto remove toast
    setTimeout(() => {
        toast.style.animation = 'slideIn 0.3s ease reverse';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}
