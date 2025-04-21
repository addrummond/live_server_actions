import { deserializeSpecials, getSerializationSpecials } from "./serialize";

let pending = {};
let loaders = {};

export const serverActions = makeServerActionsProxy([]);

function makeServerActionsProxy(moduleAndFunc) {
  const f = (...args) => {
    if (moduleAndFunc.length <= 1)
      throw new Error(`Server action${moduleAndFunc.map(p => ' ' + p).join('')} called without specifying a module`)

    return new Promise((resolve, reject) => {
      window.dispatchEvent(new CustomEvent("live-server-action", {
        detail: {
          moduleAndFunc,
          args,
          replyHandler,
          withEventId(eventId) {
            pending[eventId] = [moduleAndFunc[moduleAndFunc.length-1], resolve, reject];
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
        window.removeEventListener("live-server-action", this.liveServerActionListener);
        window.addEventListener("phx:page-loading-stop", () =>
          loaders[this.el.dataset.reactComponentName].unload(), { once: true }
        );
      }
    },
    updated() {
      if (this.el.dataset.reactComponentName) {
        if (! loaders[this.el.dataset.reactComponentName])
          throw new Error(`Component loader not found for '${this.el.dataset.reactComponentName}'`);
        loaders[this.el.dataset.reactComponentName].update(JSON.parse(this.el.dataset.reactComponentProps));
      }
    }
  };
}

const liveServerActionListener = h => e => {
  let event = {
    module_and_func: e.detail.moduleAndFunc,
    args: e.detail.args,
  };
  const specials = e.detail.args.map(a => getSerializationSpecials(a));
  if (specials.some(s => s !== null))
    event.specials = specials;
  const eventId = h.pushEvent(`live-server-action`, event, e.detail.replyHandler);
  e.detail.withEventId(eventId);
}

export function addComponentLoader(name, loader) {
  if (loaders[name])
    throw new Error(`Component loader ${name} already exists`);

  loaders[name] = loader;
}

function replyHandler(reply, ref) {
  if (pending[ref]) {
    const [name, resolve, reject] = pending[ref];
    delete pending[ref];

    if (reply.error)
      return reject(new Error(`Server action ${name} failed`));
    resolve(deserializeSpecials(reply.result, reply.specials));
  }
}
