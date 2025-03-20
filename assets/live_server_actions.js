const serverActionTimeoutSeconds = 30;

let pending = {};
let cleanupIntervalId = null;
let loaders = {};

export const serverActions = makeServerActionsProxy([]);

function makeServerActionsProxy(moduleAndFunc) {
  const f = (...args) => {
    if (moduleAndFunc.length <= 1)
      throw new Error(`Server action${moduleAndFunc.map(p => ' ' + p).join('')} called without specifying a module`)

    ensureCleanup();

    return new Promise((resolve, reject) => {
      window.dispatchEvent(new CustomEvent("live-server-action", {
        detail: {
          moduleAndFunc,
          args,
          replyHandler,
          withEventId(eventId) {
            pending[eventId] = [moduleAndFunc[moduleAndFunc.length-1], Date.now(), resolve, reject];
          }
        },
      }));
    });
  }

  return new Proxy(f, {
    get(_target, prop, _receiver) {
      return makeServerActionsProxy([...moduleAndFunc, prop]);
    }
  });
}

export function addHooks(hooks) {
  if (hooks.ServerAction)
    throw new Error("'ServerAction' hook already exists");

  const liveServerActionListener = t => e => {
    let event = {
      module_and_func: e.detail.moduleAndFunc,
      args: e.detail.args,
    };
    const specials = e.detail.args.map(a => getSerializationSpecials(a));
    if (specials.some(s => s.length > 0))
      event.specials = specials;
    const eventId = t.pushEvent(`live-server-action`, event, e.detail.replyHandler);
    e.detail.withEventId(eventId);
  }

  hooks.ServerAction = {
    mounted() {
      if (this.el.dataset.reactComponentName) {
        if (! loaders[this.el.dataset.reactComponentName])
          throw new Error(`Component loader not found for '${this.el.dataset.reactComponentName}'`);
        loaders[this.el.dataset.reactComponentName].load(this.el.childNodes[1], JSON.parse(this.el.dataset.reactComponentProps));
        this.liveServerActionListener = liveServerActionListener(this);
        window.addEventListener("live-server-action", this.liveServerActionListener);
      }
    },
    destroyed() {
      if (this.el.dataset.reactComponentName && loaders[this.el.dataset.reactComponentName]) {
        loaders[this.el.dataset.reactComponentName].unload(this.el.childNodes[1]);
        window.removeEventListener("live-server-action", this.liveServerActionListener);
        window.addEventListener("phx:page-loading-stop", () =>
          loaders[this.el.dataset.reactComponentName].unload(this.el.childNodes[1]), { once: true }
        );
      }
    }
  };
}

export function addComponentLoader(name, loader) {
  if (loaders[name])
    throw new Error(`Component loader ${name} already exists`);

  loaders[name] = loader;
}

function replyHandler(reply, ref) {
  if (pending[ref]) {
    const [name, _time, resolve, reject] = pending[ref];
    delete pending[ref];

    if (reply.error)
      return reject(new Error(`Server action ${name} failed`));
    resolve(deserializeSpecials(reply.result, reply.specials ?? []));
  }
}

function ensureCleanup() {
  if (cleanupIntervalId)
    return;

  cleanupIntervalId = setInterval(() => {
    const now = Date.now();
    for (const [ref, [name, time, _resolve, reject]] of Object.entries(pending)) {
      if (now - time > serverActionTimeoutSeconds * 1000) {
        delete pending[ref];
        setTimeout(() => reject(new Error(`Server action ${name} timed out`), 0));
      }
    }
    if (Object.keys(pending).length === 0) {
      clearInterval(cleanupIntervalId);
      cleanupIntervalId = null;
    }
  }, 1000 * 60);
}

function getSerializationSpecials(val, path=[], specials=[]) {
  if (val instanceof Date) {
    specials.push({path, type: 'Date'});
  } else if (Array.isArray(val)) {
    for (let i = 0; i < val.length; i++)
      getSerializationSpecials(val[i], [...path, i], specials);
  } else if (typeof val === 'object') {
    for (const [key, value] of Object.entries(val))
      getSerializationSpecials(value, [...path, key], specials);
  }

  return specials;
}

function deserializeSpecials(val, specials) {
  for (const {path, type} of specials) {
    let v = val;
    let upd = f => val = f(val);
    for (const p of path) {
      upd = f => v[p] = f(v[p]);
      v = v[p];
    }
    switch (type) {
      case 'Date':
        upd(d => new Date(d));
        break;
      default:
        throw new Error(`Unknown special type ${type}`);
    }
  }
  return val;
}
