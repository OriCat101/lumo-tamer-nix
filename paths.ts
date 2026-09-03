
export const PROJECT_ROOT = process.env.LUMO_TAMER_HOME || PACKAGE_ROOT;

export function resolvePackagePath(path: string): string {
  return isAbsolute(path) ? path : join(PACKAGE_ROOT, path);
}
