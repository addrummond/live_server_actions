
export function getSerializationSpecials(val, path) {
  if (val instanceof Date) {
    return mkSpecials('Date', path)
  } else if (Array.isArray(val)) {
    let subs = [];
    for (let i = 0; i < val.length; ++i)
      pushIfNotNull(subs, getSerializationSpecials(val[i], i));
    return mkSpecials('id', path, subs);
  } else if (val instanceof Set) {
    let subs = [];
    for (const elem of val) {
      if (typeof elem !== 'object')
        pushIfNotNull(subs, getSerializationSpecials(elem, elem));
    }
    return mkSpecials('Set', path, subs, [...val]);
  } else if (val instanceof Map || val instanceof FormData) {
    let subs = [];
    for (const [k, v] of val.entries()) {
      if ((typeof k === 'string' || typeof k === 'number') && !(v instanceof Blob))
        pushIfNotNull(subs, getSerializationSpecials(v, k));
    }
    return mkSpecials('shadow_id', path, subs, Object.fromEntries([...val.entries()]));
  } else if (val !== null && typeof val === 'object') {
    let subs = [];
    for (const [key, value] of Object.entries(val))
      pushIfNotNull(subs, getSerializationSpecials(value, key));
    return mkSpecials('id', path, subs);
  }
  return null;
}

function pushIfNotNull(arr, val) {
  if (val !== null)
    arr.push(val);
}

function mkSpecials(type, path, subs, shadow) {
  if (type === 'id' && subs.length === 0)
    return null;
  return { type, ...(path === null ? {} : {path}), ...(subs && subs.length > 0 ? {subs} : {}), ...(shadow && {shadow}) };
}

export function deserializeSpecials(val, specials) {
  if (specials == null)
    return val;

  switch (specials.type) {
    case 'Date':
      val = new Date(val);
      break;
    case 'Set':
      val = new Set(val);
      break;
    case 'id':
      break;
    default:
      console.warn(`Unknown special type ${specials.type}`);
  }

  for (const subSpecials of specials.subs ?? []) {
    const nullProto = Object.getPrototypeOf(val) === null;
    // hasOwnProperty works for array indices too
    if ((! nullProto && ! {}.hasOwnProperty.call(val, subSpecials.path)) || (nullProto && ! (subSpecials.path in val))) {
      console.warn(`Path ${JSON.stringify(subSpecials.path)} not found in value when deserializing specials`);
      continue;
    }

    val[subSpecials.path] = deserializeSpecials(val[subSpecials.path], subSpecials);
  }

  return val;
}
