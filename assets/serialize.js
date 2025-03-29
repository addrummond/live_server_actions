export function getSerializationSpecials(val, path=[], specials=[]) {
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

export function deserializeSpecials(val, specials) {
  outer: for (const {path, type} of specials) {
    let v = val;
    let upd = f => val = f(val);
    for (const p of path) {
      let vv = v; // rebind v so that we hang on to the value before mutation
      upd = f => vv[p] = f(vv[p]);
      if (! {}.hasOwnProperty.call(v, p)) { // hasOwnProperty works for array indices too
        console.warn(`Path ${JSON.stringify(path)} not found in value when deserializing specials`);
        continue outer;
      }
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
