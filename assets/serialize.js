export function getSerializationSpecials(val) {
  return getSerializationSpecialsHelper(val, [], []).reverse();
}

function getSerializationSpecialsHelper(val, path, specials) {
  if (val instanceof Date) {
    specials.push({path, type: 'Date'});
  } else if (Array.isArray(val)) {
    for (let i = 0; i < val.length; i++)
      getSerializationSpecialsHelper(val[i], [...path, i], specials);
  } else if (val instanceof Set) {
    let foundOne = false;
    for (const elem of val) {
      if (typeof elem !== 'object') {
        foundOne = true;
        getSerializationSpecialsHelper(elem, [...path, elem], specials);
      }
    }
    if (foundOne)
      specials.push({path, type: 'Set', shadow: [...val]});
  } else if (val instanceof Map || val instanceof FormData) {
    let foundOne = false;
    for (const [k, v] of val.entries()) {
      if ((typeof k === 'string' || typeof k === 'number') && !(v instanceof Blob)) {
        foundOne = true;
        getSerializationSpecialsHelper(v, [...path, k], specials);
      }
    }
    if (foundOne)
      specials.push({path, type: 'shadow_id', shadow: Object.fromEntries([...val.entries()])});
  } else if (typeof val === 'object') {
    for (const [key, value] of Object.entries(val))
      getSerializationSpecialsHelper(value, [...path, key], specials);
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
      case 'Set':
        upd(s => new Set(s));
        break;
      default:
        console.warn(`Unknown special type ${type}`);
    }
  }
  return val;
}
