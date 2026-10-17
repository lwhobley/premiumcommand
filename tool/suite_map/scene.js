// Premium-level suite map. Bundled into one classic script so the same page
// runs in the web app (iframe) and in the iOS/Android WebView (file:// assets,
// where ES module imports are blocked). Rebuild after editing:
//
//   npx --yes esbuild@0.24.2 tool/suite_map/scene.js --bundle --format=iife --minify \
//     --alias:three=./web/three/package/build/three.module.js --outfile=web/three/suite_map.js
//
// The page draws whatever the app sends; suite outlines and colors come from
// lib/features/suites/domain/premium_level_layout.dart. Tapping a suite, club, the
// arena floor, or the concourse posts its id back to the app.
import * as THREE from 'three';
import { OrbitControls } from '../../web/three/package/examples/jsm/controls/OrbitControls.js';

const SCALE = 0.1; // plan points to scene units
const LEVEL = 10; // height of the premium level above the arena floor, clear of the concourse beneath
const SUITE_HEIGHT = 3;
const BOWL_HEIGHT = 1.2; // lower-bowl seating blocks, standing on the arena floor

const container = document.getElementById('app');
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
container.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0xf1ede4);

const camera = new THREE.PerspectiveCamera(45, 1, 0.5, 800);
camera.position.set(0, 82, 80);

const controls = new OrbitControls(camera, renderer.domElement);
controls.target.set(0, 2, 0);
controls.enableDamping = true;
controls.maxPolarAngle = Math.PI * 0.46;
controls.minDistance = 12;
controls.maxDistance = 180;

scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8275, 1.2));
const sun = new THREE.DirectionalLight(0xffffff, 1.3);
sun.position.set(30, 90, 50);
scene.add(sun);

const floorMaterial = new THREE.MeshStandardMaterial({ color: 0x9e9a92, roughness: 0.9 });
const levelMaterial = new THREE.MeshStandardMaterial({ color: 0xe4ded2, roughness: 0.95 });
const bowlMaterial = new THREE.MeshStandardMaterial({ color: 0xcdc6b8, roughness: 0.9 });

let center = [610, 415];
let group = null;
let suiteMeshes = [];
let sectionMeshes = []; // seating sections and the level slab: they stop a tap but never select anything
let hovered = null;

const toXZ = ([x, y]) => [(x - center[0]) * SCALE, (y - center[1]) * SCALE];

// Shapes are drawn in the XY plane with plan y negated, then rotated flat so
// plan y maps to world +z and the extrusion depth becomes height.
function shapeFrom(points, ShapeType = THREE.Shape) {
  const shape = new ShapeType();
  points.forEach((p, i) => {
    const [x, z] = toXZ(p);
    if (i === 0) shape.moveTo(x, -z);
    else shape.lineTo(x, -z);
  });
  shape.closePath();
  return shape;
}

function prism(points, holes, height) {
  const shape = shapeFrom(points);
  for (const hole of holes) shape.holes.push(shapeFrom(hole, THREE.Path));
  const geometry = new THREE.ExtrudeGeometry(shape, { depth: height, bevelEnabled: false });
  geometry.rotateX(-Math.PI / 2);
  return geometry;
}

function centroid(points) {
  const sum = points.reduce((acc, p) => [acc[0] + p[0], acc[1] + p[1]], [0, 0]);
  return [sum[0] / points.length, sum[1] / points.length];
}

function labelSprite(text, { size = 2.4, background = 'rgba(255,255,255,0.92)', color = '#2a2a2a' } = {}) {
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');
  const font = '600 44px -apple-system, "Segoe UI", Roboto, sans-serif';
  ctx.font = font;
  const width = Math.ceil(ctx.measureText(text).width) + 28;
  canvas.width = width;
  canvas.height = 64;
  ctx.font = font;
  ctx.fillStyle = background;
  ctx.beginPath();
  if (ctx.roundRect) ctx.roundRect(0, 4, width, 56, 16);
  else ctx.rect(0, 4, width, 56); // older iOS WebViews
  ctx.fill();
  ctx.fillStyle = color;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, width / 2, 34);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: texture, depthTest: false }));
  sprite.scale.set((size * width) / 64, size, 1);
  sprite.renderOrder = 10;
  return sprite;
}

function dispose(object) {
  object.traverse((node) => {
    node.geometry?.dispose();
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    for (const m of materials) {
      if (!m || m === floorMaterial || m === levelMaterial || m === bowlMaterial) continue;
      m.map?.dispose();
      m.dispose();
    }
  });
}

function render(payload) {
  if (group) {
    scene.remove(group);
    dispose(group);
  }
  group = new THREE.Group();
  suiteMeshes = [];
  sectionMeshes = [];
  hovered = null;
  center = payload.center;

  // The arena floor is the open center of the building: flat at ground level, inside the
  // premium level's inner edge. The premium level wraps around it, raised above the floor.
  // When the payload has a floor entry ({id, label, color, muted}) the floor is a space like
  // the suites: colored by status and tappable. Without one it is drawn plain.
  const edge = payload.bowlEdge;
  const floor = payload.floor;
  let floorMesh;
  if (floor) {
    const selected = floor.id === payload.selected;
    floorMesh = new THREE.Mesh(
      prism(edge, [], 0.2),
      new THREE.MeshStandardMaterial({
        color: new THREE.Color(floor.muted ? 0x9e9a92 : floor.color),
        roughness: 0.9,
        emissive: new THREE.Color(selected ? 0x3a2c12 : 0x000000),
      }),
    );
    floorMesh.userData.suiteId = floor.id;
    suiteMeshes.push(floorMesh);
  } else {
    floorMesh = new THREE.Mesh(prism(edge, [], 0.2), floorMaterial);
  }
  group.add(floorMesh);
  const floorLabel = labelSprite(floor?.label ?? 'Arena floor', { size: 2.6, background: 'rgba(0,0,0,0)', color: '#f8f6f1' });
  const [labelX, labelZ] = toXZ(centroid(edge));
  floorLabel.position.set(labelX, 0.8, labelZ);
  group.add(floorLabel);

  // The concourse wraps around the lower level behind the bowl, at ground level under the
  // premium level: seen through the open gap below the level. A space like the floor
  // when the payload has a concourse entry ({id, label, color, muted}).
  const concourse = payload.concourse;
  if (concourse) {
    const selected = concourse.id === payload.selected;
    const mesh = new THREE.Mesh(
      prism(payload.footprint, [edge], 0.2),
      new THREE.MeshStandardMaterial({
        color: new THREE.Color(concourse.muted ? 0xb9b2a5 : concourse.color),
        roughness: 0.9,
        emissive: new THREE.Color(selected ? 0x3a2c12 : 0x000000),
      }),
    );
    mesh.userData.suiteId = concourse.id;
    suiteMeshes.push(mesh);
    group.add(mesh);
    // Captioned just outside the building's front wall, where the label covers nothing.
    const front = Math.max(...payload.footprint.map((p) => p[1]));
    const [x, z] = toXZ([center[0], front + 14]);
    const label = labelSprite(concourse.label, selected ? { size: 2.2, background: '#8c6a2f', color: '#ffffff' } : { size: 2.2 });
    label.position.set(x, 0.8, z);
    group.add(label);
  }

  const level = new THREE.Mesh(prism(payload.footprint, [edge], 0.6), levelMaterial);
  level.position.y = LEVEL - 0.6;
  group.add(level);
  sectionMeshes.push(level); // a tap on the level's floor must not reach the concourse below

  for (const suite of payload.suites) {
    const geometry = prism(suite.points, [], SUITE_HEIGHT);
    const selected = suite.id === payload.selected;
    const material = new THREE.MeshStandardMaterial({
      color: new THREE.Color(suite.color),
      roughness: 0.6,
      transparent: true,
      opacity: suite.muted ? 0.55 : 0.95,
      emissive: new THREE.Color(selected ? 0x3a2c12 : 0x000000),
    });
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.y = LEVEL + (selected ? 0.8 : 0);
    mesh.userData.suiteId = suite.id;
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(geometry),
      new THREE.LineBasicMaterial({ color: selected ? 0x8c6a2f : 0x2a2a2a }),
    );
    mesh.add(edges);
    group.add(mesh);
    suiteMeshes.push(mesh);

    const [cx, cz] = toXZ(centroid(suite.points));
    const label = labelSprite(suite.label, selected ? { background: '#8c6a2f', color: '#ffffff' } : {});
    label.position.set(cx, LEVEL + SUITE_HEIGHT + 1.8 + (selected ? 0.8 : 0), cz);
    if (payload.sections?.some((s) => s.space === suite.id)) {
      // Its sections carry their own labels; set the name just outside the level so it covers none.
      const length = Math.hypot(cx, cz) || 1;
      const [dx, dz] = [cx / length, cz / length];
      const reach = Math.max(...suite.points.map((p) => { const [x, z] = toXZ(p); return x * dx + z * dz; }));
      const out = reach + label.scale.x / 2 + 1;
      label.position.x = dx * out;
      label.position.z = dz * out;
    }
    group.add(label);
  }

  // Seating sections from the venue's chart. Lower-bowl sections are low blocks on the
  // floor's edge; West Club sections ({kind: 'club', space}) are outlined on top of their club.
  for (const section of payload.sections ?? []) {
    const [cx, cz] = toXZ(centroid(section.points));
    const label = labelSprite(section.id, { size: 1.4, background: 'rgba(255,255,255,0.8)' });
    if (section.kind === 'bowl') {
      const geometry = prism(section.points, [], BOWL_HEIGHT);
      const mesh = new THREE.Mesh(geometry, bowlMaterial);
      mesh.position.y = 0.2;
      mesh.add(new THREE.LineSegments(new THREE.EdgesGeometry(geometry), new THREE.LineBasicMaterial({ color: 0x8a8377 })));
      group.add(mesh);
      sectionMeshes.push(mesh);
      label.position.set(cx, 0.2 + BOWL_HEIGHT + 0.9, cz);
      group.add(label);
    } else {
      const club = suiteMeshes.find((m) => m.userData.suiteId === section.space);
      if (!club) continue;
      const outline = new THREE.LineLoop(
        new THREE.BufferGeometry().setFromPoints(section.points.map((p) => {
          const [x, z] = toXZ(p);
          return new THREE.Vector3(x, SUITE_HEIGHT + 0.03, z);
        })),
        new THREE.LineBasicMaterial({ color: 0x2a2a2a }),
      );
      club.add(outline); // children of the club, so they rise with it when it is selected
      label.position.set(cx, SUITE_HEIGHT + 0.8, cz);
      club.add(label);
    }
  }

  scene.add(group);
}

// ---- Picking -------------------------------------------------------------

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();

function pick(event) {
  const rect = renderer.domElement.getBoundingClientRect();
  pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  const hit = raycaster.intersectObjects([...suiteMeshes, ...sectionMeshes], false)[0]?.object;
  return hit?.userData.suiteId === undefined ? null : hit;
}

let down = null;
renderer.domElement.addEventListener('pointerdown', (event) => {
  down = { x: event.clientX, y: event.clientY };
});
renderer.domElement.addEventListener('pointerup', (event) => {
  if (!down) return;
  const moved = Math.hypot(event.clientX - down.x, event.clientY - down.y);
  down = null;
  if (moved > 6) return; // a drag rotates the view; only a tap selects
  const hit = pick(event);
  if (hit) post({ type: 'cutx-suite-map-select', suite: hit.userData.suiteId });
});
renderer.domElement.addEventListener('pointermove', (event) => {
  if (event.pointerType !== 'mouse' || down) return;
  const hit = pick(event);
  if (hit === hovered) return;
  if (hovered && hovered.material.emissive.getHex() === 0x222222) hovered.material.emissive.setHex(0x000000);
  hovered = hit;
  if (hovered && hovered.material.emissive.getHex() === 0x000000) hovered.material.emissive.setHex(0x222222);
  renderer.domElement.style.cursor = hit ? 'pointer' : '';
});

// ---- Messaging -----------------------------------------------------------
// Native apps inject a SuiteMapChannel and call cutxSuiteMap.render directly;
// the web app talks to this iframe with same-origin postMessage.

function post(message) {
  if (window.SuiteMapChannel) {
    window.SuiteMapChannel.postMessage(JSON.stringify(message));
  } else if (window.parent !== window) {
    window.parent.postMessage(message, window.location.origin);
  }
}

window.cutxSuiteMap = { render };
window.addEventListener('message', (event) => {
  if (event.source !== window.parent || event.origin !== window.location.origin) return;
  if (event.data?.type === 'cutx-suite-map-scene') render(event.data.payload);
});

function resize() {
  const width = container.clientWidth || 1;
  const height = container.clientHeight || 1;
  renderer.setSize(width, height, false);
  renderer.domElement.style.width = '100%';
  renderer.domElement.style.height = '100%';
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);
resize();

renderer.setAnimationLoop(() => {
  controls.update();
  renderer.render(scene, camera);
});

post({ type: 'cutx-suite-map-ready' });
